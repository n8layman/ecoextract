#' Configuration and API Key Management
#'
#' Handle API keys, environment variables, and package configuration
#'
#' This file previously contained helper functions for retrieving API keys,
#' but those have been removed. API key management is now handled automatically
#' by the underlying packages (ellmer for LLM providers, ohseer for OCR).
#' API keys are read from environment variables like ANTHROPIC_API_KEY,
#' OPENAI_API_KEY, MISTRAL_API_KEY, etc.

