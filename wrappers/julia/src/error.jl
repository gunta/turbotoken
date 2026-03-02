"""
    TurbotokenError <: Exception

General error from the turbotoken native library.
"""
struct TurbotokenError <: Exception
    message::String
end

Base.showerror(io::IO, e::TurbotokenError) = print(io, "TurbotokenError: ", e.message)

"""
    UnknownEncodingError <: Exception

Raised when an unknown encoding name is requested.
"""
struct UnknownEncodingError <: Exception
    name::String
end

Base.showerror(io::IO, e::UnknownEncodingError) = print(io, "UnknownEncodingError: unknown encoding '", e.name, "'")
