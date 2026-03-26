"use strict";

let wasm = null;

const $ = (id) => document.getElementById(id);

async function loadWasm() {
  const resp = await fetch("arche-sim.wasm");
  const { instance } = await WebAssembly.instantiate(
    await resp.arrayBuffer(),
    { env: {} },
  );
  wasm = instance.exports;
}

function readLog() {
  if (!wasm) return "";
  const ptr = wasm.sim_log_ptr();
  const len = wasm.sim_log_len();
  if (len === 0) return "";
  const buf = new Uint8Array(wasm.memory.buffer, ptr, len);
  return new TextDecoder().decode(buf);
}

function updateStats(cycle) {
  $("cycle").textContent = cycle;
  $("events").textContent = wasm.sim_event_count();
  $("log").textContent = readLog() || "(no log output)";
}

function setRunning(running) {
  $("btn-step").disabled = !running;
  $("btn-run").disabled = !running;
  $("btn-reset").disabled = !running;
}

$("btn-init").addEventListener("click", () => {
  const seed = BigInt($("seed").value);
  wasm.sim_init(seed);
  updateStats(0);
  setRunning(true);
});

$("btn-step").addEventListener("click", () => {
  const cycle = wasm.sim_step();
  updateStats(cycle);
});

$("btn-run").addEventListener("click", () => {
  let cycle = 0n;
  for (let i = 0; i < 10; i++) {
    cycle = wasm.sim_step();
  }
  updateStats(cycle);
});

$("btn-reset").addEventListener("click", () => {
  wasm.sim_reset();
  updateStats(0);
});

loadWasm().then(() => {
  $("log").textContent = "wasm loaded — enter a seed and press init";
}).catch((err) => {
  $("log").textContent = "failed to load wasm: " + err.message;
});
