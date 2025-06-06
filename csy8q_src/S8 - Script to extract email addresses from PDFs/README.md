# Extracting authors' contact information from CHI 2019 program and PDFs

## Workflow

* Manually create the following folders. (This step is necessary because OSF doesn't permit uploading empty folders):
   * lib
   * output/cermxml
   * output/pdf_first_page

* Install [Java Development Kit](https://www.oracle.com/technetwork/java/javase/downloads/jdk12-downloads-5295953.html) (Tested with JDK 12)

* Download CERMINE binary and place [`cermine-impl-1.13-jar-with-dependencies.jar`](https://maven.ceon.pl/artifactory/kdd-releases/pl/edu/icm/cermine/cermine-impl/1.13/cermine-impl-1.13-jar-with-dependencies.jar) in `lib` folder (next to this README file).

* Go through the header of `R/*.R` files and install relevant packages

* Place PDF files from the CHI 2019 proceedings in the `input/pdf` folder

* Run `R/process_pdf.R`. This will combine the following information:
   * PDF information extracted by two methods (via XML and via text)
   * Complete metatdata without email address from `chi2019_papers.csv`
   * List of the first authors' email address from our 2018 survey from `chi2018_invitations.csv`
   
* The output will be an Excel file to be manually checked and corrected.


## Sources of data files

* `input/chi2019_papers.csv` is a list of CHI 2019 paper metadata without email address. This is extracted from publicly available [CHI 2019 program in JSON format](https://fbr.me/data/chi19-schedule.json) by Kashyap Todi.

* `input/chi2018_invitations.csv` contains a list of emails of the first authors of CHI 2018. Initially, we obtained these emails from Confer by Florian Ecthler. Several email addresses were manually updated during the process of sending out survey email in 2018 by Chat Wacharamanotham.
