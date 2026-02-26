"""turbotoken public API."""

from __future__ import annotations

from typing import TYPE_CHECKING, Any

__all__ = [
    "Encoding",
    "get_encoding",
    "encoding_for_model",
    "list_encoding_names",
    "train_encoding_from_iterator",
    "train_mergeable_ranks_from_iterator",
]
__version__ = "0.1.0.dev0"

_CORE_EXPORTS = {"Encoding", "get_encoding", "encoding_for_model", "list_encoding_names"}
_TRAINING_EXPORTS = {"train_encoding_from_iterator", "train_mergeable_ranks_from_iterator"}

if TYPE_CHECKING:
    from .core import Encoding, encoding_for_model, get_encoding, list_encoding_names
    from .training import train_encoding_from_iterator, train_mergeable_ranks_from_iterator


def __getattr__(name: str) -> Any:
    if name in _CORE_EXPORTS:
        from .core import Encoding, encoding_for_model, get_encoding, list_encoding_names

        exports = {
            "Encoding": Encoding,
            "get_encoding": get_encoding,
            "encoding_for_model": encoding_for_model,
            "list_encoding_names": list_encoding_names,
        }
        value = exports[name]
        globals()[name] = value
        return value

    if name in _TRAINING_EXPORTS:
        from .training import train_encoding_from_iterator, train_mergeable_ranks_from_iterator

        exports = {
            "train_encoding_from_iterator": train_encoding_from_iterator,
            "train_mergeable_ranks_from_iterator": train_mergeable_ranks_from_iterator,
        }
        value = exports[name]
        globals()[name] = value
        return value

    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
