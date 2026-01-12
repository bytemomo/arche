
[default]
default:
    @just --list

build:
    @just build-mode ReleaseFast

build-dbg:
    @just build-mode Debug

run:
    @just run-mode ReleaseFast

run-dbg:
    @just run-mode Debug

run-mode mode:
    zig build run -Doptimize={{mode}} -Dlog_level={{mode}}

build-mode mode:
    zig build -Doptimize={{mode}} -Dlog_level={{mode}}

debug:
    @echo "Starting debug session..."
    tmux new-session -d -s arche-debug 'zig build run; read'
    tmux split-window -h -t arche-debug 'sleep 1 && gdb -q -ex "target remote :1234" -ex "set disassembly-flavor intel" zig-out/img/kyber.elf'
    tmux attach -t arche-debug

debug-kill:
    tmux kill-session -t arche-debug 2>/dev/null || true

clean:
    rm -rf zig-out .zig-cache
