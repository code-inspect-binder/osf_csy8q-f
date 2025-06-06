
# path for input
pdf_root <- "input/pdf"
metadata_2018_path <- "input/chi2018_invitations.csv"
metadata_2019_path <- "input/chi2019_papers.csv"

# path for intermediate and output files
first_page_root <- "output/pdf_first_page"
cermxml_root <- "output/cermxml"
png_root <- "output/png"


#===============================================================================
library(tidyverse)
import::from(pdftools, pdf_subset, pdf_text)
import::from(xml2, read_xml, xml_find_first, xml_text)
import::from(magick, image_read_pdf, image_info, image_write, image_crop)
import::from(tools, file_path_sans_ext)
import::from(fuzzyjoin, stringdist_left_join)
import::from(stringdist, stringdist)
import::from(openxlsx, createWorkbook, addWorksheet, writeDataTable, insertImage, setRowHeights, setColWidths, saveWorkbook)

#===============================================================================
# process PDF files

# compute all paths
pdf_paths <- list.files(path = file.path(pdf_root), pattern = "*.pdf", recursive = TRUE, full.names = TRUE)
first_page_paths = file.path(first_page_root, basename(pdf_paths))
png_paths <- file.path(png_root, paste0(file_path_sans_ext(basename(pdf_paths)), ".png"))


# extract the first page
dontcare <- 
  pdf_paths %>% 
  map2(first_page_paths, pdf_subset, pages = 1)


# extract the head and convert it to image

extract_pdf_top <- function(pdf_path) {
  page_img <- image_read_pdf(pdf_path, page = 1, density = 72)
  width <- image_info(page_img)$width
  height <- image_info(page_img)$height
  left <- 0
  top <- 75
  height <- height / 4
  image_crop(page_img, geometry = sprintf("%fx%f+%f+%f", width, height, left, top))  
}

dontcare <- 
  first_page_paths %>% 
  map(extract_pdf_top) %>% 
  map2(png_paths, image_write)


# use CERMINE to convert the first page to XML

cermine_sh <- sprintf("java -cp lib/cermine-impl-1.13-jar-with-dependencies.jar pl.edu.icm.cermine.ContentExtractor -path %s -outputs jats -override", first_page_root)
system(cermine_sh)
src_cermxml_paths <- list.files(path = file.path(first_page_root), pattern = "*.cermxml", full.names = TRUE)
cermxml_paths <- file.path(cermxml_root, basename(src_cermxml_paths))
dontcare <- file.rename(src_cermxml_paths, cermxml_paths)


#-------------------------------------------------------------------------------
# extract emails directly from PDF text

first_email_from_pdf_text <- function(a_pdf_path) {
  str_extract(pdf_text(a_pdf_path), "[_a-z0-9-]+(\\.[_a-z0-9-]+)*@[a-z0-9-]+(\\.[a-z0-9-]+)*(\\.[a-z]{2,4})")
}

txt_first_emails <- 
tibble(
  txt_file_name = file_path_sans_ext(basename(first_page_paths)),
  txt_email = first_page_paths %>% map_chr(first_email_from_pdf_text)
)

write_csv(txt_first_emails, "output/txt_first_emails.csv")


#-------------------------------------------------------------------------------
# extract metadata from XML

xpath_find_first <- function(xml_node, xpath) {
  xml_text(xml_find_first(xml_node, xpath))
}

xmls <- 
  cermxml_paths %>% 
  map(read_xml)

xml_metadata <- 
  tibble(
    xml_file_name   = file_path_sans_ext(basename(cermxml_paths)),
    xml_title       = map_chr(xmls, xpath_find_first, xpath = "//article-title"),
    xml_email       = map_chr(xmls, xpath_find_first, xpath = "//email"),
    xml_author_name = map_chr(xmls, xpath_find_first, xpath = "//contrib[@contrib-type='author']/string-name")
  ) %>% 
  replace_na(list(xml_title = "")) %>% 
  arrange(xml_file_name)

write_csv(xml_metadata, "output/metadata_from_xml.csv")

#===============================================================================
# other data sources

# CHI 2019 program data: has exact title, DOI, and the name of the first author
prog_metadata <- 
  read_csv("input/chi2019_papers.csv", col_types = "cccic______") %>% 
  filter(AuthorNumber == 1) %>% 
  select(-AuthorNumber, prog_id = PaperID, prog_doi = DOI, prog_title = Title, prog_author_name = AuthorName)


# CHI 2018 survey email addresses
cols_spec <- cols_only(firstname = col_character(),
                       lastname = col_character(),
                       email = col_character())
chi18 <- 
  read_csv("input/chi2018_invitations.csv", col_types = cols_spec) %>% 
  mutate(chi18_author_name = str_c(firstname, lastname, sep = " ")) %>% 
  select(chi18_author_name, chi18_email = email)

#===============================================================================
# joining data

# all data originated from pdf
pdf_metadata <- 
  xml_metadata %>% 
  left_join(txt_first_emails, by = c(xml_file_name = "txt_file_name"))

# fuzzy-join program-data with (1) pdf-data and (2) data from CHI 2018 survey
matched_title <- 
  prog_metadata %>% 
  stringdist_left_join(pdf_metadata, by = c(prog_title = "xml_title"), distance_col = "title_distance", max_dist = 5) %>% 
  stringdist_left_join(chi18, by = c(prog_author_name = "chi18_author_name"), distance_col = "author_distance", max_dist = 2)

# select the first email to retain based on how good the author name matches
matched_email <- 
  matched_title %>% 
  mutate(email = case_when(
    is.na(txt_email) & is.na(xml_email) ~ chi18_email,  # if no email found, try using CHI 2018 email
    is.na(xml_email) ~ txt_email,                       # if XML doens't find an email use the text email           
    stringdist(xml_author_name, prog_author_name) < 3 ~ xml_email, # for XML email: use only if XML author name fuzzy-matches program author name
    TRUE ~ txt_email))                                  # otherwise, use the email from text (which may be NA)

write_csv(matched_email, "output/matched_email.csv")


#===============================================================================
# generate Excel file for checking

data_xls <- 
  matched_email %>% 
  select(email,
         first_author = prog_author_name, 
         title = prog_title, 
         file_name = xml_file_name,
         alt_email = chi18_email,
         prog_id,
         doi = prog_doi) %>% 
  arrange(file_name)


# initialize Excel sheet
excel_wb <- createWorkbook()
addWorksheet(excel_wb, "paper_data")
setRowHeights(excel_wb, "paper_data", rows = 2:(nrow(data_xls) + 1), 65)
setColWidths(excel_wb, "paper_data", cols = 1:4, widths = c(36, 25, 25, 30))

# add data (assuming that the data_xls is sorted by file_name)
writeDataTable(excel_wb, "paper_data", data_xls, startCol = 2)
for (i in 1:nrow(data_xls)) {
  a_file_name <- data_xls$file_name[[i]]
  if(is.na(a_file_name)) next
  png_file_path <- file.path(png_root, paste0(a_file_name, ".png"))
  insertImage(excel_wb, "paper_data", png_file_path, 
              startRow = i + 1, startCol = 1, 
              width = 612 * 1.5, height = 198 * 1.5, unit = "px")
}

# save
saveWorkbook(excel_wb, "output/to_check.xlsx", overwrite = TRUE)
