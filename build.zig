const std = @import("std");

const out_dir_name = "img";

pub fn build(b: *std.Build) void {
    const cpu_arch = b.option(
        std.Target.Cpu.Arch,
        "arch",
        "Target architecture",
    ) orelse .x86_64;

    const options = b.addOptions();
    setup(b, options);
    const optimize = b.standardOptimizeOption(.{});

    setupKyber(b, cpu_arch, options, optimize);
    setupLogos(b, cpu_arch, options, optimize);
    setupTests(b);
    setupSimHeadless(b, cpu_arch, options, optimize);
    setupSimWeb(b, cpu_arch, options, optimize);
    setupQemu(b);
}

// -- Options ---------------------------------------------------------

fn setup(b: *std.Build, options: *std.Build.Step.Options) void {
    const s = b.option([]const u8, "log_level", "log_level") orelse "Info";
    const map = .{
        .{ "Debug", std.log.Level.debug },
        .{ "Info", std.log.Level.info },
        .{ "Warn", std.log.Level.warn },
        .{ "Error", std.log.Level.err },
        .{ "ReleaseFast", std.log.Level.warn },
        .{ "Release", std.log.Level.warn },
        .{ "ReleaseSafe", std.log.Level.warn },
    };
    const level: std.log.Level = inline for (map) |entry| {
        if (std.mem.eql(u8, s, entry[0])) break entry[1];
    } else @panic("Invalid log level");
    options.addOption(std.log.Level, "log_level", level);
}

// -- Architecture paths ----------------------------------------------

fn halPath(arch: std.Target.Cpu.Arch) []const u8 {
    return switch (arch) {
        .x86_64 => "kyber/arch/x86_64/hal/hal.zig",
        else => @panic("Unsupported architecture"),
    };
}

// -- Kyber (hypervisor kernel) ---------------------------------------

fn setupKyber(
    b: *std.Build,
    cpu_arch: std.Target.Cpu.Arch,
    options: *std.Build.Step.Options,
    optimize: std.builtin.OptimizeMode,
) void {
    const hal = b.createModule(.{ .root_source_file = b.path(halPath(cpu_arch)) });

    const kyber = b.addExecutable(.{
        .name = "kyber.elf",
        .root_module = b.createModule(.{
            .root_source_file = b.path("kyber/entry.zig"),
            .target = b.resolveTargetQuery(.{
                .cpu_arch = cpu_arch,
                .os_tag = .freestanding,
                .ofmt = .elf,
            }),
            .optimize = optimize,
            .code_model = .large,
            .pic = true,
        }),
        .linkage = .static,
        .use_llvm = true,
    });
    kyber.root_module.addOptions("option", options);
    kyber.root_module.addImport("hal", hal);
    kyber.setLinkerScript(b.path("kyber/linker.ld"));
    b.installArtifact(kyber);

    const install = b.addInstallFile(
        kyber.getEmittedBin(),
        b.fmt("{s}/{s}", .{ out_dir_name, kyber.name }),
    );
    install.step.dependOn(&kyber.step);
    b.getInstallStep().dependOn(&install.step);
}

// -- Logos (UEFI bootloader) -----------------------------------------

fn setupLogos(
    b: *std.Build,
    cpu_arch: std.Target.Cpu.Arch,
    options: *std.Build.Step.Options,
    optimize: std.builtin.OptimizeMode,
) void {
    const logos = b.addExecutable(.{
        .name = "BOOTX64.EFI",
        .root_module = b.createModule(.{
            .root_source_file = b.path("logos/main.zig"),
            .target = b.resolveTargetQuery(.{ .cpu_arch = cpu_arch, .os_tag = .uefi }),
            .optimize = optimize,
        }),
        .linkage = .static,
        .use_llvm = true,
    });
    logos.subsystem = .EfiApplication;
    logos.root_module.addOptions("option", options);
    b.installArtifact(logos);

    const install = b.addInstallFile(
        logos.getEmittedBin(),
        b.fmt("{s}/efi/boot/{s}", .{ out_dir_name, logos.name }),
    );
    install.step.dependOn(&logos.step);
    b.getInstallStep().dependOn(&install.step);
}

// -- Simulation (DST) ------------------------------------------------

fn setupSim(
    b: *std.Build,
    cpu_arch: std.Target.Cpu.Arch,
    options: *std.Build.Step.Options,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    const sim_hal = b.createModule(.{ .root_source_file = b.path("sim/hal/hal.zig") });
    sim_hal.addImport("core", b.createModule(.{
        .root_source_file = b.path("sim/core.zig"),
    }));

    // The kernel module uses the sim HAL — same code, different hardware.
    const kernel = b.createModule(.{ .root_source_file = b.path("kyber/entry.zig") });
    kernel.addImport("hal", sim_hal);
    kernel.addOptions("option", options);

    const sim = b.addExecutable(.{
        .name = "arche-sim",
        .root_module = b.createModule(.{
            .root_source_file = b.path("sim/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    sim.root_module.addImport("hal", sim_hal);
    sim.root_module.addImport("core", sim_hal.import_table.get("core").?);
    sim.root_module.addImport("kernel", kernel);

    _ = cpu_arch;
    return sim;
}

fn setupSimHeadless(
    b: *std.Build,
    cpu_arch: std.Target.Cpu.Arch,
    options: *std.Build.Step.Options,
    optimize: std.builtin.OptimizeMode,
) void {
    const sim = setupSim(b, cpu_arch, options, b.graph.host, optimize);
    const install = b.addInstallArtifact(sim, .{
        .dest_dir = .{ .override = .{ .custom = "sim" } },
    });
    const run = b.addRunArtifact(sim);
    run.step.dependOn(&install.step);
    b.step("sim-headless", "Run DST simulation (host-native)").dependOn(&run.step);
}

fn setupSimWeb(
    b: *std.Build,
    cpu_arch: std.Target.Cpu.Arch,
    options: *std.Build.Step.Options,
    optimize: std.builtin.OptimizeMode,
) void {
    const target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding });
    const sim = setupSim(b, cpu_arch, options, target, optimize);
    sim.entry = .disabled;
    sim.rdynamic = true;
    sim.stack_size = 4 * 1024 * 1024;

    const web_dir = "sim/web";
    const install_wasm = b.addInstallFile(sim.getEmittedBin(), b.fmt("{s}/arche-sim.wasm", .{web_dir}));
    install_wasm.step.dependOn(&sim.step);
    const install_html = b.addInstallFile(b.path("sim/web/index.html"), b.fmt("{s}/index.html", .{web_dir}));
    const install_js = b.addInstallFile(b.path("sim/web/index.js"), b.fmt("{s}/index.js", .{web_dir}));

    const serve = b.addSystemCommand(&.{
        "python3",                                      "-m", "http.server", "8080", "--directory",
        b.fmt("{s}/{s}", .{ b.install_path, web_dir }),
    });
    serve.step.dependOn(&install_wasm.step);
    serve.step.dependOn(&install_html.step);
    serve.step.dependOn(&install_js.step);
    b.step("sim-web", "Build and serve DST simulation (wasm32)").dependOn(&serve.step);
}

// -- Tests -----------------------------------------------------------

fn setupTests(b: *std.Build) void {
    const test_step = b.step("test", "Run unit tests");

    // Kernel tests — use entry.zig as root so file imports resolve.
    const hal = b.createModule(.{ .root_source_file = b.path("sim/hal/hal.zig") });
    const core = b.createModule(.{ .root_source_file = b.path("sim/core.zig") });
    hal.addImport("core", core);
    const kernel_test = b.createModule(.{
        .root_source_file = b.path("kyber/tests.zig"),
        .target = b.graph.host,
    });
    test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = kernel_test })).step);

    // Sim HAL tests
    const hal_test = b.createModule(.{
        .root_source_file = b.path("sim/hal/hal.zig"),
        .target = b.graph.host,
    });
    hal_test.addImport("core", core);
    test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = hal_test })).step);
}

// -- QEMU runner -----------------------------------------------------

fn setupQemu(b: *std.Build) void {
    const qemu = b.addSystemCommand(&.{
        "qemu-system-x86_64",
        "-m",
        "512M",
        "-bios",
        "/usr/share/edk2/x64/OVMF.4m.fd",
        "-drive",
        b.fmt("file=fat:rw:{s}/{s},format=raw", .{ b.install_path, out_dir_name }),
        "-nographic",
        "-serial",
        "mon:stdio",
        "-no-reboot",
        "-enable-kvm",
        "-cpu",
        "host",
        "-s",
        "-device",
        "isa-debug-exit,iobase=0xf4,iosize=0x04",
    });
    qemu.step.dependOn(b.getInstallStep());
    b.step("run", "Run QEMU").dependOn(&qemu.step);
}
