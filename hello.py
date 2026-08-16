import os

MESSAGES = {
    "en": "Hello from my new MacBook Pro",
    "zh": "你好，来自我的新 MacBook Pro",
}


def get_language():
    for var in ("LC_ALL", "LC_MESSAGES", "LANG"):
        if os.environ.get(var, "").startswith("zh"):
            return "zh"
    return "en"


print(MESSAGES[get_language()])
