# Test Data

## test_paper.md

**IMPORTANT: This is a completely fake, synthetic scientific paper created solely for testing the ecoextract package.**

- **All data is fictional** - No real research was conducted
- **All authors are fake** - Smith, Johnson, Williams are invented names
- **All locations are fake** - Roosevelt Grove, Cascade Valley, etc. do not exist
- **All findings are fabricated** - The bat interaction data is made up
- **All citations are fake** - Referenced papers do not exist

### Purpose

This test document is used to:
1. Demonstrate the extraction workflow
2. Test the package functionality
3. Validate schema customization
4. Provide examples in documentation

### Expected Extractions

The document should extract approximately 4 co-roosting interaction events:

1. Myotis lucifugus + Myotis yumanensis (June 15, 2022)
2. Myotis volans + Myotis evotis (July 3, 2022)  
3. Myotis lucifugus + M. yumanensis + M. californicus (July 20, 2022)
4. Myotis volans + Myotis thysanodes (August 5, 2022)

### Usage

```r
# Read test paper
test_paper <- readr::read_file(
  system.file("extdata", "test_paper.md", package = "ecoextract")
)

# Extract interactions
result <- extract_interactions(
  document_content = test_paper
)
```

**DO NOT USE THIS DATA FOR ANY SCIENTIFIC PURPOSE**
