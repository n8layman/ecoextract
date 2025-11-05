1. Inputs loaded: OCR data ( 55352 chars), OCR audit ( 67 chars), 14 records, refinement prompt ( 3867 chars, hash: 423853d4 ) has strange spacing the spaces before 55352, before 67, before 11 and before 3867 in refinement logging. I think this is just a paste vs paste0 style issue. Don't have this problem for extraction.
2. Double check that tests actually detect errors for the integration tests. Remember that errors aren't made explicit but captured in the status of the output tibble. At the end of each ecoextract::process_documents() run through you should check:
   ```
   test_df <- test |> select(ocr_status, audit_status, extraction_status,          refinement_status) |> as.matrix()
   any(!test_df %in% c("skipped", "completed"))
   ```
   That's how you tell if integration tests pass or fail! If any of those columns are not skipped or completed for any row the test failed.
3. Still getting row duplication on refinement. Check the db and add a test that runs refinement on a single paper 4 times. I still think we have work to do on the layout. Maybe extraction always looks for new rows. We provide the records we already have as context. Refinement always seeks to improve rows that already exist. To make generic species descriptions more specific (do not ever ever use specific examples in the prompt but an example for you might be tree-hollows -> eucalyptus trees). Remember I do not want specific examples in the prompt they could bias the model. In both we need to respect human edits and never change those rows.
