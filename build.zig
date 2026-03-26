const std = @import("std");

const out_dir_name = "img";
const cpu_arch: std.Target.Cpu.Arch = .x86_64;

pub fn build(b: *std.Build) void {
    const options = b.addOptions();
    setup(b, options);

    const optimize = b.standardOptimizeOption(.{});
    _ = setupKyber(b, options, optimize);
    _ = setupLogos(b, options, optimize);
    setupTests(b, options);
    setupSimHeadless(b, options, optimize);
    setupSimWeb(b, options, optimize);

    // use qemu as run method
    const qemu_args = [_][]const u8{
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
        // This adds to qemu a device that listen on I/O port 0xf4 and
        // when write a byte to that port qemu exits.
        "-device",
        "isa-debug-exit,iobase=0xf4,iosize=0x04",
    };
    const qemu_cmd = b.addSystemCommand(&qemu_args);
    qemu_cmd.step.dependOn(b.getInstallStep());

    const run_qemu_cmd = b.step("run", "Run QEMU");
    run_qemu_cmd.dependOn(&qemu_cmd.step);
}

fn setup(b: *std.Build, options: *std.Build.Step.Options) void {
    const s_log_level = b.option([]const u8, "log_level", "log_level") orelse "Info";

    const log_level: std.log.Level = b: {
        const eql = std.mem.eql;
        break :b if (eql(u8, s_log_level, "Debug"))
            .debug
        else if (eql(u8, s_log_level, "Info"))
            .info
        else if (eql(u8, s_log_level, "Warn"))
            .warn
        else if (eql(u8, s_log_level, "Error"))
            .err

            // This are usefull when we want to have a certain log level
            // with certain build types
        else if (eql(u8, s_log_level, "ReleaseFast"))
            .warn
        else if (eql(u8, s_log_level, "Release"))
            .warn
        else if (eql(u8, s_log_level, "ReleaseSafe"))
            .warn
        else
            @panic("Invalid log level");
    };

    options.addOption(std.log.Level, "log_level", log_level);
}

fn createTypesModule(b: *std.Build) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = b.path("common/types.zig"),
    });
}

fn createArchModule(b: *std.Build, comptime arch: std.Target.Cpu.Arch, types_module: *std.Build.Module) *std.Build.Module {
    const arch_path = switch (arch) {
        .x86_64 => "common/arch/x86_64.zig",
        else => @compileError("Unsupported architecture"),
    };
    const mod = b.createModule(.{
        .root_source_file = b.path(arch_path),
    });
    mod.addImport("types", types_module);
    return mod;
}

fn createLogModule(b: *std.Build, writer_mod: *std.Build.Module) *std.Build.Module {
    const mod = b.createModule(.{
        .root_source_file = b.path("common/log.zig"),
    });
    mod.addImport("writer", writer_mod);
    return mod;
}

fn createWriterModule(b: *std.Build, writer_path: std.Build.LazyPath) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = writer_path,
    });
}

fn createBootInfoModule(b: *std.Build, types_module: *std.Build.Module) *std.Build.Module {
    const mod = b.createModule(.{
        .root_source_file = b.path("common/boot_info.zig"),
    });
    mod.addImport("types", types_module);
    return mod;
}

fn setupKyber(b: *std.Build, options: *std.Build.Step.Options, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
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
    kyber.setLinkerScript(b.path("kyber/linker.ld"));
    const kyber_types = createTypesModule(b);
    kyber.root_module.addOptions("option", options);
    kyber.root_module.addImport("types", kyber_types);
    kyber.root_module.addImport("arch", createArchModule(b, cpu_arch, kyber_types));
    kyber.root_module.addImport("boot_info", createBootInfoModule(b, kyber_types));
    const kyber_hal = b.createModule(.{
        .root_source_file = b.path("kyber/arch/x86_64/hal/hal.zig"),
    });
    kyber_hal.addImport("types", kyber_types);
    kyber.root_module.addImport("hal", kyber_hal);
    const kyber_writer = createWriterModule(b, b.path("kyber/arch/x86_64/serial.zig"));
    kyber_writer.addImport("hal", kyber_hal);
    kyber.root_module.addImport("log", createLogModule(b, kyber_writer));
    b.installArtifact(kyber);

    const install_kyber = b.addInstallFile(
        kyber.getEmittedBin(),
        b.fmt("{s}/{s}", .{ out_dir_name, kyber.name }),
    );
    install_kyber.step.dependOn(&kyber.step);
    b.getInstallStep().dependOn(&install_kyber.step);

    return kyber;
}

fn setupLogos(b: *std.Build, options: *std.Build.Step.Options, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
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
    const logos_types = createTypesModule(b);
    logos.root_module.addOptions("option", options);
    logos.root_module.addImport("types", logos_types);
    logos.root_module.addImport("arch", createArchModule(b, cpu_arch, logos_types));
    logos.root_module.addImport("boot_info", createBootInfoModule(b, logos_types));
    logos.root_module.addImport("log", createLogModule(b, createWriterModule(b, b.path("logos/uefi/console.zig"))));
    b.installArtifact(logos);

    const install_logos = b.addInstallFile(
        logos.getEmittedBin(),
        b.fmt("{s}/efi/boot/{s}", .{ out_dir_name, logos.name }),
    );
    install_logos.step.dependOn(&logos.step);
    b.getInstallStep().dependOn(&install_logos.step);

    return logos;
}

// --- Simulation (DST) targets ---

fn createSimHal(b: *std.Build) *std.Build.Module {
    const sim_core = b.createModule(.{
        .root_source_file = b.path("sim/core.zig"),
    });
    const sim_hal = b.createModule(.{
        .root_source_file = b.path("sim/hal/hal.zig"),
    });
    sim_hal.addImport("core", sim_core);
    return sim_hal;
}

fn addSimImports(root: *std.Build.Module, sim_hal: *std.Build.Module, options: *std.Build.Step.Options) void {
    const b = root.owner;
    root.addOptions("option", options);
    root.addImport("hal", sim_hal);
    root.addImport("core", sim_hal.import_table.get("core").?);

    const sim_types = createTypesModule(b);
    const sim_boot_info = createBootInfoModule(b, sim_types);
    const sim_writer = b.createModule(.{
        .root_source_file = b.path("kyber/arch/x86_64/serial.zig"),
    });
    sim_writer.addImport("hal", sim_hal);
    const sim_log = createLogModule(b, sim_writer);
    root.addImport("log", sim_log);
    root.addImport("types", sim_types);
    root.addImport("boot_info", sim_boot_info);

    const sim_kernel = b.createModule(.{
        .root_source_file = b.path("kyber/entry.zig"),
    });
    sim_kernel.addOptions("option", options);
    sim_kernel.addImport("hal", sim_hal);
    sim_kernel.addImport("log", sim_log);
    sim_kernel.addImport("types", sim_types);
    sim_kernel.addImport("boot_info", sim_boot_info);
    root.addImport("kernel", sim_kernel);
}

fn setupTests(b: *std.Build, _: *std.Build.Step.Options) void {
    const test_step = b.step("test", "Run unit tests");
    const types_mod = createTypesModule(b);

    // Common module tests
    const common_paths = [_][]const u8{
        "common/types.zig",
        "common/arch/x86_64/types.zig",
        "common/arch/x86_64/paging.zig",
        "common/arch/x86_64/layout.zig",
        "common/boot_info.zig",
    };

    for (common_paths) |path| {
        const mod = b.createModule(.{
            .root_source_file = b.path(path),
            .target = b.graph.host,
        });
        mod.addImport("types", types_mod);
        const t = b.addTest(.{ .root_module = mod });
        test_step.dependOn(&b.addRunArtifact(t).step);
    }

    // Simulation HAL tests
    const sim_hal = createSimHal(b);
    const hal_test = b.createModule(.{
        .root_source_file = b.path("sim/hal/hal.zig"),
        .target = b.graph.host,
    });
    hal_test.addImport("core", sim_hal.import_table.get("core").?);
    const t = b.addTest(.{ .root_module = hal_test });
    test_step.dependOn(&b.addRunArtifact(t).step);
}

fn setupSimHeadless(b: *std.Build, options: *std.Build.Step.Options, optimize: std.builtin.OptimizeMode) void {
    const sim_hal = createSimHal(b);

    const sim_exe = b.addExecutable(.{
        .name = "arche-sim",
        .root_module = b.createModule(.{
            .root_source_file = b.path("sim/main.zig"),
            .target = b.graph.host,
            .optimize = optimize,
        }),
    });
    addSimImports(sim_exe.root_module, sim_hal, options);

    const install_sim = b.addInstallArtifact(sim_exe, .{
        .dest_dir = .{ .override = .{ .custom = "sim" } },
    });

    const run_sim = b.addRunArtifact(sim_exe);
    run_sim.step.dependOn(&install_sim.step);

    const sim_step = b.step("sim-headless", "Run DST simulation (host-native)");
    sim_step.dependOn(&run_sim.step);
}

fn setupSimWeb(b: *std.Build, options: *std.Build.Step.Options, optimize: std.builtin.OptimizeMode) void {
    const sim_hal = createSimHal(b);
    const web_dir = "sim/web";

    const sim_wasm = b.addExecutable(.{
        .name = "arche-sim",
        .root_module = b.createModule(.{
            .root_source_file = b.path("sim/main.zig"),
            .target = b.resolveTargetQuery(.{
                .cpu_arch = .wasm32,
                .os_tag = .freestanding,
            }),
            .optimize = optimize,
        }),
    });
    sim_wasm.entry = .disabled;
    sim_wasm.rdynamic = true;
    sim_wasm.stack_size = 4 * 1024 * 1024; // 4 MiB stack for large static structs
    addSimImports(sim_wasm.root_module, sim_hal, options);

    const install_wasm = b.addInstallFile(
        sim_wasm.getEmittedBin(),
        b.fmt("{s}/arche-sim.wasm", .{web_dir}),
    );
    install_wasm.step.dependOn(&sim_wasm.step);

    const install_html = b.addInstallFile(
        b.path("sim/web/index.html"),
        b.fmt("{s}/index.html", .{web_dir}),
    );
    const install_js = b.addInstallFile(
        b.path("sim/web/index.js"),
        b.fmt("{s}/index.js", .{web_dir}),
    );

    const serve = b.addSystemCommand(&.{
        "python3",                                      "-m", "http.server", "8080", "--directory",
        b.fmt("{s}/{s}", .{ b.install_path, web_dir }),
    });
    serve.step.dependOn(&install_wasm.step);
    serve.step.dependOn(&install_html.step);
    serve.step.dependOn(&install_js.step);

    const wasm_step = b.step("sim-web", "Build and serve DST simulation (wasm32)");
    wasm_step.dependOn(&serve.step);
}
