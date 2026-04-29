#!/usr/bin/env xonsh
"""Yobleck's Yet Another "Artificial Intelligence" Interface
requires: 
    python-requests, python-wcwidth, python-setproctitle
    curl, ollama, jq, pgrep, pkill, unbuffer, nnn
    TODO? convert to pure python to drop curl/jq/etc.

TODO store all config info in the ollama json file
    notes, tts/asr options etc.

TODO generate new json file from scratch

NOTE
startup
start server
choose model from list
optionally load tts and asr (into vram before ollama or make them over flow into ram?)

tui
list of numbered options along the bottom
1.quick add text to end of context
    optionally asr
send to server
stream response
optionally send sentences to tts

2. edit full context in editor of choice
3. edit server settings specifically?
"""
import json
import os
import string  # https://docs.python.org/3/library/string.html
import sys
import termios  # https://man7.org/linux/man-pages/man3/termios.3.html
import threading  # needed?
import time

import requests
import wcwidth
try:
    import setproctitle
    setproctitle.setproctitle("Yobleck's Yet Another Artificial Intelligence Interface")
except ModuleNotFoundError:
    log("warning: setproctitle not installed")

### Utils #################################################
version: str = "0.1.0"

config: dict = {
    "editor": "micro",
    "filepicker": ["nnn", "-p", "-"],
    "default_session_dir": "./",
    "llm_api_url": "http://localhost:11434/api/chat",
    "default_session": '{"model": "filler_model", "stream": false, "temp_options": {"num_ctx": 4096}, "messages": [{"role": "user", "content": "this is filler text"}]}',
    "auto_start_llm": False,
    "auto_kill_llm": False,
    "tts_server": "./tts_server.py",
    "auto_start_tts": False,
    "asr_model": "",
    "auto_start_asr": False,
}

if len(sys.argv) > 1 and sys.argv[1] in ["h", "-h", "help", "-help", "--help"]:
    print("""YYAAII $version HELP SCREEN:
        session files are ollama .json api context files with some extra fields tacked on
        """)


def log(i) -> None:
    """Logging function"""
    with open(f"./yyaaii.log", "a") as f:
        f.write(f"{time.asctime()}: {str(i)}\n")


# check if non python dependencies exist
for prog in ["pgrep", "pkill", "ollama", "jq", "nnn", "unbuffer"]:
    if "not in $PATH or aliases" in $(which @(prog) 2>&1):
        log(f"error: {prog} not found")
        sys.exit(1)


def getch(blocking: bool = True, bytes_to_read: int = 1) -> str:
    # TODO for esc sequences do a time based (.1s) read of all available bytes
    fd = sys.stdin.fileno()
    old_settings = termios.tcgetattr(fd)
    new = list(old_settings)
    new[0] &= ~(termios.IGNBRK | termios.BRKINT | termios.PARMRK |
                termios.ISTRIP | termios.INLCR | termios.IGNCR | termios.ICRNL | termios.IXON)
    # new[1] &= ~termios.OPOST  # cfmakeraw()
    new[3] &= ~(termios.ICANON | termios.ECHO | termios.ECHONL | termios.ISIG | termios.IEXTEN)
    new[6][termios.VMIN] = 1 if blocking else 0
    new[6][termios.VTIME] = 0  # 0 is faster but inputs appear on screen?
    termios.tcsetattr(fd, termios.TCSADRAIN, new)
    try:
        ch = sys.stdin.read(bytes_to_read)
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)
    return ch


ctrl_chars = {  # NOTE not using thsi right now. just for reference
    "\x03": "^C", "\x11": "^Q",
    "\x7f": "bk", "\r\n": "en",
    "\x05": "^E", "\x0f": "^O",
    "\x0c": "^L", "\x10": "^P",
    "\x14": "^T", "\x13": "^S",
    "\x17": "^W", "\x19": "^Y",
}


esc_chars = {"[A": "up", "[B": "dn", "[C": "rt", "[D": "lf", "[F": "end", "[H": "home", "[[A": "F1",
             "[[B": "F2", "[[C": "F3", "OS": "F4", "[Z": "shft+tb", "[5~": "pgup", "[6~": "pgdn",  # "OR": "F3"
             "[15~": "F5", "[17~": "F6", "[18~": "F7", "[19~": "F8", "[20~": "F9", "[21~": "F10",
             "[23~": "F11", "[24~": "F12",}  # f keys broken?


def handle_esc() -> str:  # TODO only using keys with length 3?
    """https://en.wikipedia.org/wiki/ANSI_escape_code
    I don't know if this holds across all computers/keyboards
    or if my setup just weird?
    BUG: holding down key that uses less than 4 esc chars will capture
    first char of next sequence early so next characters are captured as plain text"""
    a = getch(False, 4)
    if a in esc_chars.keys():
        return esc_chars[a]
    elif a == "":
        return "esc"
    return ""


### Startup functions #####################################
def start_llm_server():
    """ make this generic for different providers? probably not"""
    if not $(pgrep ollama):
        ollama serve 2>&1 > /dev/null &


def start_tts_server():
    # https://github.com/QwenLM/Qwen3-TTS/blob/main/pyproject.toml
    !(@(config["tts_server"]))


def start_asr_server():
    # https://github.com/QwenLM/Qwen3-ASR/blob/main/pyproject.toml
    # whisper-cli
    pass


def load_session() -> str:
    """look for json files in config default dir"""
    file = $(@(config["filepicker"]))
    if file:
        return file
    else:
        # TODO new session file if file not selected
        pass


### Functions #############################################
def pick_llm_model() -> str:
    model_list = $(ollama list).split("\n")[1:-1]
    model_list = [m.split(" ")[0] for m in model_list]
    print("\x1b[2J\x1b[H\x1b[?25l")
    [print(i, m) for i, m in enumerate(model_list)]
    selected = input("select model:\n")
    model = model_list[int(selected)]
    j = $(@json jq . @(session))
    j["model"] = model
    with open(session, "w") as f:
        json.dump(j, f, indent=4)
    return model


def append_message_template(role: str) -> None:
    """roles are user and assistant"""
    # using this snippet 3 times. DRY WET?
    j = $(@json jq . @(session))
    j["messages"].append({"role": role, "content": ""})
    with open(session, "w") as f:
        json.dump(j, f, indent=4)


def update_last_message(stream_fragment) -> None:
    j = $(@json jq . @(session))
    j["messages"][-1]["content"] += stream_fragment
    with open(session, "w") as f:
        json.dump(j, f, indent=4)


def send_cxt_to_server():
    """send the context to the llm server to be processed"""
    # TODO make this async/threaded so user can still scroll? or auto force scroll?
    if $(jq .stream @(session)) == "true":
        r = requests.post(config["llm_api_url"], data=$(jq . @(session)), stream=True)
        append_message_template("assistant")
        for line in r.iter_lines():
            update_last_message(json.loads(line.decode())["message"]["content"])
            # if buffer_len > screen_size.lines - 6 then scroll += 1?
            draw_ui(context=True)  # NOTE update in real time. BUG over draws UI bar?

    else:
        # first @ for curl read from file and @ for py->bash
        reply = $(curl @(config["llm_api_url"]) -d @@(session) 2>/dev/null)
        j = $(@json jq . @(session))
        j["messages"].append(json.loads(reply)["message"])
        with open(session, "w") as f:
            json.dump(j, f, indent=4)


def send_to_tts_server(text: str) -> None:
    """temporary test. this is shit
    qwen python /home/yobleck/ai/qwen_tts/text_input.txt
    """
    with open("./tts_input.txt", "w") as f:
        f.write(text)


def draw_ui(top_bar=False, context=False, keybinds=False, user_input=False, bot_bar=False, full_draw=False) -> None:
    """draw the ui. if all are False then assume redraw all (set all to True). else only redraw True"""
    screen_size = os.get_terminal_size()  # NOTE used in place of sigwinch
    if screen_size.columns < 100 or screen_size.lines < 15:
        log("warning: screen size too small. cols>=100 and lines>=15 recommended")

    print("\x1b[?25l", end="")  # needed but why?
    if top_bar or full_draw:
        print(f"\x1b[0;0H\x1b[2K┤YYAAII {version}├─┤Session: {session.rsplit('/', 1)[1]}├─┤ Model: {model}├", end="")
    
    if context or full_draw:
        draw_context_chunk(screen_size, scroll)
    
    if keybinds or full_draw:
        print(f"\x1b[{screen_size.lines - 4};0H\x1b[2K┌{'─' * (screen_size.columns - 2)}┐")
        print(f" \x1b[7m^Q\x1b[27m Quit          "
              f" \x1b[7m^E\x1b[27m Edit context        "
              f" \x1b[7mEn\x1b[27m Quick append"
              f" \x1b[7m^R\x1b[27m ASR input         \n"
              f" \x1b[7m^P\x1b[27m Pick model    "  # NOTE might need \x1b[2K here if overwritten by context
              f" \x1b[7m^S\x1b[27m Send to server      "
              f" \x1b[7m^Y\x1b[27m Load session"
              f" \x1b[7m^T\x1b[27m TTS last message    "
              f" \x1b[7m^L\x1b[27m full refresh screen", end="")
    
    if user_input or full_draw:
        print(f"\x1b[{screen_size.lines - 1};0H\x1b[2K Quick append: {input_buffer}", end="")
    
    if bot_bar or full_draw:
        print(f"\x1b[{screen_size.lines};0H\x1b[2K└{'─' * (screen_size.columns - 2)}┘", end="")
    sys.stdout.flush()


def draw_context_chunk(screen_size, scroll) -> None:
    """print the section of the context visible on screen"""
    # TODO should this print out the entire file instead of just the message list?
    mes = $(unbuffer jq .messages @(session))  # unbuffer to preserve colors
    mes = mes.split("\n")
    out = []
    for line in mes:  # split lines longer than screen width into multiple
        if wcwidth.width(line) < screen_size.columns:
            out.append(line)
        else:
            split = wcwidth.wrap(line, width=screen_size.columns-1)
            for s in split:
                out.append(s)

    global buffer_len
    buffer_len = len(out)

    for x in range(2, screen_size.lines - 6):  # clear context area of any left overs
        print(f"\x1b[{x};0H\x1b[2K")
    print(f"\x1b[1;0H")
    for line in out[scroll:scroll + screen_size.lines - 6]:
        print("\x1b[2K" + line)


### Main Program ##########################################

if config["auto_start_llm"]:
    start_llm_server()
if config["auto_start_tts"]:
    start_tts_server()
if config["auto_start_asr"]:
    start_asr_server()
session: str = load_session()
model = $(jq .model @(session))
scroll: int = 0
input_buffer: str = ""
buffer_len: int = 0

print("\x1b[2J\x1b[H\x1b[?25l")
draw_ui(full_draw=True)
while True:
    char = getch()
    log(f"input: {char}")

    if char in ["\x03", "\x11"]:  # ^C ^Q
        break

    elif char == "\x05":  # ^E
        @(config["editor"]) @(session)
        draw_ui(full_draw=True)

    elif char == "\r":  # Enter
        # NOTE for quick one line additions only only
        append_message_template("user")
        update_last_message(input_buffer)
        input_buffer = ""
        draw_ui(user_input=True, context=True)

    elif char == "\x10":  # ^P
        model = pick_llm_model()
        draw_ui(full_draw=True)

    elif char == "\x13":  # ^S
        send_cxt_to_server()
        draw_ui(context=True)

    elif char == "\x19":  # ^Y load session
        session = load_session()
        model = $(jq .model @(session))
        scroll = 0
        buffer_len = 0
        draw_ui(full_draw=True)

    elif char == "\x0c":  # ^L force redraw the screen
        draw_ui(full_draw=True)

    elif char == "\x7f":  # Backspace
        input_buffer = input_buffer[:-1]
        draw_ui(user_input=True)

    # TODO ^T ^R
    elif char == "\x14":  # ^T send last message to TTS server
        # send_to_tts_server($(jq .messages[-1].content @(session)))
        with open(session, "r") as f:
            send_to_tts_server(json.load(f)["messages"][-1]["content"])

    elif char == "\x1b":
        res = handle_esc()
        if res == "up":  # scroll context up
            scroll -= 1
            if scroll < 0:
                scroll = 0
        if res == "dn":  # scroll context dn
            scroll += 1
            if scroll > buffer_len - 4:  # leave a bit on screen
                scroll = buffer_len - 4
        draw_ui(context=True)  # NOTE awkward. will have to change if handling any other esc seq

    elif char in string.printable.replace("\n\r", ""):
        input_buffer += char
        draw_ui(user_input=True)
    

if config["auto_kill_llm"]:
    pkill ollama
print("\x1b[2J\x1b[3J\x1b[H\x1b[?25h", end="")
