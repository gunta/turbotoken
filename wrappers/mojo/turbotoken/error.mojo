@value
struct TurbotokenError(Stringable):
    var message: String

    fn __init__(out self, message: String):
        self.message = message

    fn __str__(self) -> String:
        return "TurbotokenError: " + self.message
