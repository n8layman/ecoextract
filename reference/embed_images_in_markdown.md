# Embed Images in Markdown (Internal Helper)

Replace markdown image bibliography with HTML img tags containing base64
data

## Usage

``` r
embed_images_in_markdown(markdown_text, images_data, page_num = 1)
```

## Arguments

- markdown_text:

  Markdown text

- images_data:

  Parsed images JSON object

- page_num:

  Page number to process (default: 1, "all" for all pages)

## Value

Processed markdown with embedded images
