# YYAAII
Yobleck's Yet Another Artificial Intelligence Interface

## Dependencies
  - xonsh
  - python 3.14 (3.10+ probably works)
      - requests
      - wcwidth
      - setproctitle (optional)
  - jq (json parsing)
  - ollama (inference engine)
  - nnn (can be replaced in config)
  - unbuffer (expect)
  - p[grep/kill]
  - firejail (for sandboxing ollama)
  - switch-netns (to access ollama from outside sandbox)
  - [qwen3-tt.cpp](https://github.com/predict-woo/qwen3-tts.cpp)
      - change -DGGML_METAL to -DGGML_[CUDA/VULKAN] etc.
      - change -j4 to how many ever threads you want to run faster

## Notes
 can edit built in config variable in yyaaii.xsh

 TODO qwen3-asr or whisper.cpp, voice design with qwen3-tts, auto create new session
