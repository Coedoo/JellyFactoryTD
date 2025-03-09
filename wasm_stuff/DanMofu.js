function GetDMImports(wmi) {
    const files = new FilesInterface(wmi);
    const audio = new WebAudioInterface(wmi);
    const utility = new Utility(wmi);

    return {
        "audio": audio.getAudioInterface(),
        "files": files.getInterface(),
        "utility": utility.getInterface(),
    }
}

class Utility {
    constructor(wasmMemoryInterface) {
        this.wmi = wasmMemoryInterface;
    }

    getInterface() {
        return {
            SetCanvasSize: (width, height) => {
                let canvas = document.getElementById("game_viewport");
                canvas.width = width;
                canvas.height = height;
            }
        }
    }
}

class FilesInterface {
    constructor(wasmMemoryInterface) {
        this.wmi = wasmMemoryInterface;
    }

    getInterface() {
        return {
            LoadFile: (pathPtr, pathLen, callback) => {
                let path = this.wmi.loadString(pathPtr, pathLen)
                
                const req = new XMLHttpRequest();
                req.open("GET", path);
                // req.setRequestHeader("Cache-Control", "no-cache, no-store, max-age=0");
                req.responseType = "arraybuffer";

                let that = this;
                req.onload = (e) => {
                    const odin_ctx = this.wmi.exports.default_context_ptr();

                    const arraybuffer = req.response;
                    let ptr = that.wmi.exports.wasm_alloc(arraybuffer.byteLength, odin_ctx)
                    let src = new Uint8Array(arraybuffer)
                    let dest = new Uint8Array(that.wmi.memory.buffer, ptr, arraybuffer.byteLength);

                    // console.log(e)

                    dest.set(src)
                    that.wmi.exports.DoFileCallback(ptr, arraybuffer.byteLength, callback, odin_ctx)
                };

                req.send(null);
            }
        }
    }
}

class WebAudioInterface {
    constructor(wasmMemoryInterface) {
        const AudioContext = window.AudioContext || window.webkitAudioContext;

        this.wmi = wasmMemoryInterface;
        this.audioCtx = new AudioContext();

        this.sounds = new Map();
        this.playingSounds = new Map();
    }


    getAudioInterface() {
        return {
            Load: (filePtr, fileLen) => {
                let file = this.wmi.loadBytes(filePtr, fileLen);
                let content = file.buffer.slice(filePtr, filePtr + fileLen)

                let that = this;
                this.audioCtx.decodeAudioData(content, (buffer) => {
                    console.log("Decoded audio clip...")
                    that.sounds.set(filePtr, buffer);
                },
                (error) => {
                    console.error("Failed to decode audio:", error);
                })
            },

            Play: (key, volume, pan, delay) => {
                if(this.sounds.has(key)) {
                    let gainNode = this.audioCtx.createGain();
                    gainNode.gain.value = volume;

                    let panNode = this.audioCtx.createStereoPanner();
                    panNode.pan.value = pan;

                    let src = this.audioCtx.createBufferSource();
                    src.buffer = this.sounds.get(key);

                    src.connect(gainNode)
                       .connect(panNode)
                       .connect(this.audioCtx.destination);
                    
                    let time = this.audioCtx.currentTime + delay;
                    src.start(time);

                    this.playingSounds.set(key, src);
                }
                else {
                    console.error("Sound doesn't exists in dictionary");
                }
            },

            Stop: (key) => {
                let sound = this.playingSounds.get(key);
                if(sound !== undefined) {
                    sound.stop();
                }
            }

        }
    }
}

// Insert hack to make sound autoplay on Chrome as soon as the user interacts with the tab:
// https://developers.google.com/web/updates/2018/11/web-audio-autoplay#moving-forward

// the following function keeps track of all AudioContexts and resumes them on the first user
// interaction with the page. If the function is called and all contexts are already running,
// it will remove itself from all event listeners.
(function () {
    // An array of all contexts to resume on the page
    const audioContextList = [];

    // An array of various user interaction events we should listen for
    const userInputEventNames = [
        "click",
        "contextmenu",
        "auxclick",
        "dblclick",
        "mousedown",
        "mouseup",
        "pointerup",
        "touchend",
        "keydown",
        "keyup",
    ];

    // A proxy object to intercept AudioContexts and
    // add them to the array for tracking and resuming later
    self.AudioContext = new Proxy(self.AudioContext, {
        construct(target, args) {
            const result = new target(...args);
            audioContextList.push(result);
            return result;
        },
    });

    // To resume all AudioContexts being tracked
    function resumeAllContexts(_event) {
        let count = 0;

        audioContextList.forEach((context) => {
            if (context.state !== "running") {
                context.resume();
            } else {
                count++;
            }
        });

        // If all the AudioContexts have now resumed then we unbind all
        // the event listeners from the page to prevent unnecessary resume attempts
        // Checking count > 0 ensures that the user interaction happens AFTER the game started up
        if (count > 0 && count === audioContextList.length) {
            userInputEventNames.forEach((eventName) => {
                document.removeEventListener(eventName, resumeAllContexts);
            });
        }
    }

    // We bind the resume function for each user interaction
    // event on the page
    userInputEventNames.forEach((eventName) => {
        document.addEventListener(eventName, resumeAllContexts);
    });
})();