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
                xhr.setRequestHeader("Cache-Control", "no-cache, no-store, max-age=0");
                xhr.setRequestHeader("Expires", "Tue, 01 Jan 1980 1:00:00 GMT");
                xhr.setRequestHeader("Pragma", "no-cache");
                req.responseType = "arraybuffer";

                let that = this;
                req.onload = (e) => {
                    const odin_ctx = this.wmi.exports.default_context_ptr();

                    const arraybuffer = req.response;
                    let ptr = that.wmi.exports.wasm_alloc(arraybuffer.byteLength, odin_ctx)
                    let src = new Uint8Array(arraybuffer)
                    let dest = new Uint8Array(that.wmi.memory.buffer, ptr, arraybuffer.byteLength);

                    // console.log(req.response.byteLength)

                    dest.set(src)
                    that.wmi.exports.DoFileCallback(ptr, arraybuffer.byteLength, callback, odin_ctx)
                };

                req.send(null);
            }
        }
    }
}