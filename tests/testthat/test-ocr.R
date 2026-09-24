# OCR Output Tests
# Tests for reading OCR pages and embedding stored images

#' Save a two-page Mistral-style document whose pages both use img-0.jpeg
#' for different images
local_ocr_images_document <- function(db_path, env = parent.frame()) {
  test_file <- withr::local_tempfile(fileext = ".pdf", .local_envir = env)
  writeLines("test content", test_file)
  pages <- list(
    list(index = 0, markdown = "Page one ![img-0.jpeg](img-0.jpeg) and ![missing](img-9.jpeg)"),
    list(index = 1, markdown = "Page two ![img-0.jpeg](img-0.jpeg) and ![](img-7.jpeg)")
  )
  images <- list(pages = list(
    list(images = list(list(id = "img-0.jpeg", image_base64 = "data:image/jpeg;base64,PAGEONE"))),
    list(images = list(list(id = "img-0.jpeg", image_base64 = "PAGETWO")))
  ))
  save_document_to_db(db_path, test_file, metadata = list(
    document_content = as.character(jsonlite::toJSON(pages, auto_unbox = TRUE)),
    ocr_images = as.character(jsonlite::toJSON(images, auto_unbox = TRUE))
  ))
}

test_that("embed_page_images matches placeholders to images by stored id", {
  images <- list(list(id = "img-1.jpeg", image_base64 = "data:image/png;base64,ONE"))

  result <- embed_page_images("![fig](img-1.jpeg) ![alt text](img-2.jpeg) ![](img-3.jpeg)", images)

  expect_match(result, '<img src="data:image/png;base64,ONE" alt="fig"', fixed = TRUE)
  expect_match(result, "alt text", fixed = TRUE)
  expect_match(result, "img-3.jpeg", fixed = TRUE)
  expect_false(grepl("![", result, fixed = TRUE))
})

test_that("get_ocr_pages embeds each page's own images", {
  db_path <- local_test_db()
  doc_id <- local_ocr_images_document(db_path)

  pages <- get_ocr_pages(doc_id, db_path)

  expect_length(pages, 2)
  expect_match(pages[1], "base64,PAGEONE", fixed = TRUE)
  expect_false(grepl("PAGETWO", pages[1], fixed = TRUE))
  # Stored base64 without a data URI prefix gets one
  expect_match(pages[2], "data:image/jpeg;base64,PAGETWO", fixed = TRUE)
  expect_false(grepl("PAGEONE", pages[2], fixed = TRUE))
  # Placeholders with no stored image become plain text, never a dangling src
  expect_match(pages[1], "and missing$")
  expect_match(pages[2], "and img-7.jpeg$")
})

test_that("get_ocr_pages returns page markdown unchanged without embedding", {
  db_path <- local_test_db()
  doc_id <- local_ocr_images_document(db_path)

  pages <- get_ocr_pages(doc_id, db_path, embed_images = FALSE)

  expect_equal(pages[1], "Page one ![img-0.jpeg](img-0.jpeg) and ![missing](img-9.jpeg)")
})

test_that("get_ocr_pages errors for OCR output without page markdown", {
  db_path <- local_test_db()
  test_file <- withr::local_tempfile(fileext = ".pdf")
  writeLines("test content", test_file)
  # Tensorlake stores structured page fields, not markdown
  content <- jsonlite::toJSON(list(list(page_number = 1, text = "Body")), auto_unbox = TRUE)
  doc_id <- save_document_to_db(db_path, test_file,
                                metadata = list(document_content = as.character(content)))

  expect_error(get_ocr_pages(doc_id, db_path), "no page markdown")
})

test_that("get_ocr_html_preview embeds images on every page", {
  db_path <- local_test_db()
  doc_id <- local_ocr_images_document(db_path)

  html <- as.character(get_ocr_html_preview(doc_id, db_path, page_num = "all"))

  expect_match(html, "PAGEONE", fixed = TRUE)
  expect_match(html, "PAGETWO", fixed = TRUE)
})
