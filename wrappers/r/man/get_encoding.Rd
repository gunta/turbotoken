\name{get_encoding}
\alias{get_encoding}
\title{Get a BPE encoding by name}
\usage{
get_encoding(name)
}
\arguments{
\item{name}{Character string. The encoding name, e.g. \code{"cl100k_base"},
\code{"o200k_base"}, \code{"r50k_base"}, \code{"p50k_base"}, \code{"p50k_edit"},
\code{"gpt2"}, \code{"o200k_harmony"}.}
}
\value{
A \code{turbotoken_encoding} S3 object that can be used with
\code{\link{encode}}, \code{\link{decode}}, \code{\link{count_tokens}}, and
\code{\link{is_within_token_limit}}.
}
\description{
Load a BPE encoding by name, downloading the rank file if it is not
already cached locally.
}
\examples{
\dontrun{
enc <- get_encoding("cl100k_base")
tokens <- encode(enc, "hello world")
decode(enc, tokens)
}
}
