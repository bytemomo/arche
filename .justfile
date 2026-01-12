
[default]
default:
    @just --list

build mode:
    zig build run -Doptimize={{mode}} -Dlog_level={{mode}}
