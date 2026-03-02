from pathlib import Path
from collections import List
from .registry import get_encoding_spec


fn cache_dir() -> String:
    var xdg = String("")
    try:
        xdg = os.getenv("XDG_CACHE_HOME")
    except:
        pass
    if len(xdg) > 0:
        return xdg + "/turbotoken"
    var home = String("")
    try:
        home = os.getenv("HOME")
    except:
        home = "."
    return home + "/.cache/turbotoken"


fn ensure_rank_file(name: String) raises -> String:
    var spec = get_encoding_spec(name)
    var url = spec.rank_file_url
    # Extract filename from URL
    var last_slash = 0
    for i in range(len(url)):
        if url[i] == "/":
            last_slash = i
    var file_name = url[last_slash + 1 :]
    var dir = cache_dir()
    var local_path = dir + "/" + file_name

    var p = Path(local_path)
    if p.exists():
        return local_path

    raise Error("Rank file not found at " + local_path + ". Please download it manually from " + url)


fn read_rank_file(name: String) raises -> List[UInt8]:
    var file_path = ensure_rank_file(name)
    var p = Path(file_path)
    var data = p.read_bytes()
    var result = List[UInt8]()
    for i in range(len(data)):
        result.append(data[i])
    return result
