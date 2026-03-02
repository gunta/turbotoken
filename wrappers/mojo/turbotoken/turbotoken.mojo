from .encoding import Encoding
from .registry import get_encoding_spec, model_to_encoding, list_encoding_names
from .rank_cache import read_rank_file
from .ffi import ffi_version


fn get_encoding(name: String) raises -> Encoding:
    var spec = get_encoding_spec(name)
    var rank_data = read_rank_file(spec.name)
    return Encoding(spec.name, spec, rank_data)


fn get_encoding_for_model(model: String) raises -> Encoding:
    var encoding_name = model_to_encoding(model)
    return get_encoding(encoding_name)


fn version() -> String:
    return ffi_version()
