#' Configuration and API Key Management
#' 
#' Handle API keys, environment variables, and package configuration


#' Get Anthropic API key from environment
#' @return API key string or NULL if not found
get_anthropic_key <- function() {
  key <- Sys.getenv("ANTHROPIC_API_KEY")
  if (key == "") {
    # Try alternative environment variable names
    key <- Sys.getenv("CLAUDE_API_KEY")
  }
  if (key == "") return(NULL)
  return(key)
}

#' Get Mistral API key from environment
#' @return API key string or NULL if not found
get_mistral_key <- function() {
  key <- Sys.getenv("MISTRAL_API_KEY")
  if (key == "") return(NULL)
  return(key)
}

