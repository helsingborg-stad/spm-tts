# TTS

TTS provides a common interface for Text To Speech services implementing the `TTSService` protocol.

## Usage 

```
import AudioSwitchboard
import TTS
import MyTTSService

let switchboard = AudioSwitchboard()

let tts = TTS(service: MyTTSService(audioSwitchBoard: switchboard))
tts.play(.init("This is my awesome app"))
```

## TODO

- [_] add list of available services
- [_] add support for multiple services
- [_] code-documentation
- [_] write tests
- [_] complete package documentation
