#!/usr/bin/env python
# https://github.com/predict-woo/qwen3-tts.cpp
import os
import queue
import shutil
import subprocess
import threading
import time


# TODO deal with OOM error when ollama taking it all
def generate(text):  # line, filename
    for filename, line in enumerate(text):
        print(f"generating {filename}...")
        cmd = (f"/home/yobleck/ai/qwen_tts_cpp/qwen3-tts.cpp/build/qwen3-tts-cli "
               f"-m /home/yobleck/ai/qwen_tts_cpp/qwen3-tts.cpp/models -t \"{line}\" "
               f"-r /home/yobleck/ai/qwen_tts_cpp/qwen3-tts.cpp/examples/ch0091_00_shirona_0000_en.wav "
               f"-o /tmp/qwentts/{filename}.wav")
        subprocess.run(cmd,  # TODO write to /tmp file or io.bytes?
                       stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE,
                       stdin=subprocess.PIPE,
                       shell=True)
        q.put(filename)
    # return filename


def speak():
    while True:
        try:
            filename = q.get()
        except queue.ShutDown:
            break
        print(f"playing {filename}...")
        subprocess.run(f"paplay /tmp/qwentts/{filename}.wav",
                       stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE,
                       stdin=subprocess.PIPE,
                       shell=True)
        q.task_done()


print("starting server...")

current_mod_time = os.path.getmtime("./tts_input.txt")
while True:
    check_time = os.path.getmtime("./tts_input.txt")
    if check_time != current_mod_time:
        print("processing input...")
        with open("./tts_input.txt", "r+") as f:
            # filter out \n and empty lines and quotes and other crap that breaks stuff
            text = list(filter(None, f.read().replace("\"", "").replace("\'", "").replace("*", "").splitlines()))
            # print(text)
            # exit()
            f.truncate(0)  # zero out file
        current_mod_time = os.path.getmtime("./tts_input.txt")

        if text[0] == "tts server exit":
            break

        shutil.rmtree("/tmp/qwentts/", ignore_errors=True)
        os.mkdir("/tmp/qwentts/")

        # threaded wav generation and playback
        q = queue.Queue()
        t_speak = threading.Thread(target=speak, daemon=None)
        t_speak.start()
        t_gen = threading.Thread(target=generate, args=(text,), daemon=None)
        t_gen.start()
        # for i, line in enumerate(text):
        #     q.put(generate(line, i))
        t_gen.join()
        q.shutdown()
        t_speak.join()
        print("done")

        # NOTE old non threaded version
        # for i, t in enumerate(text):
        #     print("processing input...")
        #     cmd = (f"/home/yobleck/ai/qwen_tts_cpp/qwen3-tts.cpp/build/qwen3-tts-cli "
        #            f"-m /home/yobleck/ai/qwen_tts_cpp/qwen3-tts.cpp/models -t \"{t}\" "
        #            f"-r /home/yobleck/ai/qwen_tts_cpp/qwen3-tts.cpp/examples/ch0091_00_shirona_0000_en.wav "
        #            f"-o /tmp/qwentts/{i}.wav")
        #     subprocess.run(cmd,  # TODO write to /tmp file or io.bytes?
        #                    # stdout=subprocess.PIPE,
        #                    # stderr=subprocess.PIPE,
        #                    stdin=subprocess.PIPE,
        #                    shell=True)
        #     print("playing output...")
        #     subprocess.run(f"paplay /tmp/qwentts/{i}.wav",
        #                    # stdout=subprocess.PIPE,
        #                    # stderr=subprocess.PIPE,
        #                    stdin=subprocess.PIPE,
        #                    shell=True)
    time.sleep(0.5)

# TODO voice design then clone
