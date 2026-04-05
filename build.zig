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
    setupTests(b, cpu_arch);
    setupSimHeadless(b, cpu_arch, options, optimize);
    setupSimWeb(b, cpu_arch, options, optimize);
    setupQemu(b);
}

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

fn halPath(arch: std.Target.Cpu.Arch) []const u8 {
    return switch (arch) {
        .x86_64 => "kyber/arch/x86_64/hal/hal.zig",
        else => @panic("Unsupported architecture"),
    };
}

fn archPath(arch: std.Target.Cpu.Arch) []const u8 {
    return switch (arch) {
        .x86_64 => "kyber/arch/x86_64/init.zig",
        else => @panic("Unsupported architecture"),
    };
}

const KernelModules = struct {
    hal: *std.Build.Module,
    core: *std.Build.Module,
    mem: *std.Build.Module,
    arch: *std.Build.Module,
};

fn createKernelModules(
    b: *std.Build,
    cpu_arch: std.Target.Cpu.Arch,
    hal: *std.Build.Module,
) KernelModules {
    const core = b.createModule(.{
        .root_source_file = b.path("kyber/core/core.zig"),
    });
    core.addImport("hal", hal);

    const mem = b.createModule(.{
        .root_source_file = b.path("kyber/mem/mem.zig"),
    });
    mem.addImport("core", core);

    const arch = b.createModule(.{
        .root_source_file = b.path(archPath(cpu_arch)),
    });
    arch.addImport("hal", hal);
    arch.addImport("core", core);
    arch.addImport("mem", mem);

    return .{ .hal = hal, .core = core, .mem = mem, .arch = arch };
}

fn setupKyber(
    b: *std.Build,
    cpu_arch: std.Target.Cpu.Arch,
    options: *std.Build.Step.Options,
    optimize: std.builtin.OptimizeMode,
) void {
    const hal = b.createModule(.{
        .root_source_file = b.path(halPath(cpu_arch)),
    });
    const mods = createKernelModules(b, cpu_arch, hal);

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
    kyber.root_module.addImport("hal", mods.hal);
    kyber.root_module.addImport("core", mods.core);
    // arch needs kernel for kmain; wire after root module exists.
    mods.arch.addImport("kernel", kyber.root_module);
    kyber.root_module.addImport("arch", mods.arch);
    kyber.setLinkerScript(b.path("kyber/linker.ld"));
    b.installArtifact(kyber);

    const install = b.addInstallFile(
        kyber.getEmittedBin(),
        b.fmt("{s}/{s}", .{ out_dir_name, kyber.name }),
    );
    install.step.dependOn(&kyber.step);
    b.getInstallStep().dependOn(&install.step);
}

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
            .target = b.resolveTargetQuery(.{
                .cpu_arch = cpu_arch,
                .os_tag = .uefi,
            }),
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

fn setupSim(
    b: *std.Build,
    cpu_arch: std.Target.Cpu.Arch,
    options: *std.Build.Step.Options,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    const sim_hal = b.createModule(.{
        .root_source_file = b.path("sim/hal/hal.zig"),
    });
    const sim_core = b.createModule(.{
        .root_source_file = b.path("sim/core.zig"),
    });
    sim_hal.addImport("core", sim_core);

    const mods = createKernelModules(b, cpu_arch, sim_hal);

    const kernel = b.createModule(.{
        .root_source_file = b.path("kyber/entry.zig"),
    });
    kernel.addImport("hal", sim_hal);
    kernel.addImport("core", mods.core);
    kernel.addImport("arch", mods.arch);
    kernel.addOptions("option", options);
    mods.arch.addImport("kernel", kernel);

    const sim = b.addExecutable(.{
        .name = "arche-sim",
        .root_module = b.createModule(.{
            .root_source_file = b.path("sim/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    sim.root_module.addImport("hal", sim_hal);
    sim.root_module.addImport("core", sim_core);
    sim.root_module.addImport("kernel", kernel);

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
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });
    const sim = setupSim(b, cpu_arch, options, target, optimize);
    sim.entry = .disabled;
    sim.rdynamic = true;
    sim.stack_size = 4 * 1024 * 1024;

    const web_dir = "sim/web";
    const install_wasm = b.addInstallFile(
        sim.getEmittedBin(),
        b.fmt("{s}/arche-sim.wasm", .{web_dir}),
    );
    install_wasm.step.dependOn(&sim.step);
    const install_html = b.addInstallFile(
        b.path("sim/web/index.html"),
        b.fmt("{s}/index.html", .{web_dir}),
    );
    const install_js = b.addInstallFile(
        b.path("sim/web/index.js"),
        b.fmt("{s}/index.js", .{web_dir}),
    );

    const serve = b.addSystemCommand(&.{
        "python3",
        "-m",
        "http.server",
        "8080",
        "--directory",
        b.fmt("{s}/{s}", .{ b.install_path, web_dir }),
    });
    serve.step.dependOn(&install_wasm.step);
    serve.step.dependOn(&install_html.step);
    serve.step.dependOn(&install_js.step);
    b.step("sim-web", "Build and serve DST simulation (wasm32)")
        .dependOn(&serve.step);
}

fn setupTests(b: *std.Build, cpu_arch: std.Target.Cpu.Arch) void {
    const test_step = b.step("test", "Run unit tests");

    const sim_hal = b.createModule(.{
        .root_source_file = b.path("sim/hal/hal.zig"),
    });
    const sim_core = b.createModule(.{
        .root_source_file = b.path("sim/core.zig"),
    });
    sim_hal.addImport("core", sim_core);

    const mods = createKernelModules(b, cpu_arch, sim_hal);

    // Core module tests
    const core_test = b.createModule(.{
        .root_source_file = b.path("kyber/core/core.zig"),
        .target = b.graph.host,
    });
    core_test.addImport("hal", sim_hal);
    test_step.dependOn(
        &b.addRunArtifact(b.addTest(.{ .root_module = core_test })).step,
    );

    // Arch mm tests
    const arch_mm_test = b.createModule(.{
        .root_source_file = b.path("kyber/arch/x86_64/mm/tests.zig"),
        .target = b.graph.host,
    });
    arch_mm_test.addImport("core", mods.core);
    test_step.dependOn(
        &b.addRunArtifact(b.addTest(.{ .root_module = arch_mm_test })).step,
    );

    // Sim HAL tests
    const hal_test = b.createModule(.{
        .root_source_file = b.path("sim/hal/hal.zig"),
        .target = b.graph.host,
    });
    hal_test.addImport("core", sim_core);
    test_step.dependOn(
        &b.addRunArtifact(b.addTest(.{ .root_module = hal_test })).step,
    );
}

fn setupQemu(b: *std.Build) void {
    const qemu = b.addSystemCommand(&.{
        "qemu-system-x86_64",
        "-m",
        "512M",
        "-bios",
        "/usr/share/edk2/x64/OVMF.4m.fd",
        "-drive",
        b.fmt("file=fat:rw:{s}/{s},format=raw", .{
            b.install_path,
            out_dir_name,
        }),
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
