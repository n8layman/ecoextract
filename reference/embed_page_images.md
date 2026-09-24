# Embed a page's OCR images in its markdown (internal)

Replaces each markdown image placeholder `![alt](src)` with an `<img>`
tag when an image with `id == src` is stored for the page, and with the
alt text (or the source, if the alt text is empty) otherwise. Image
numbering restarts on every page, so this works on one page at a time.

## Usage

``` r
embed_page_images(markdown, images)
```

## Arguments

- markdown:

  Markdown text of one page

- images:

  List of the page's stored images, each with `id` and `image_base64`

## Value

Markdown with images embedded
