const std = @import("std");

const out_dir_name = "img";
const cpu_arch: std.Target.Cpu.Arch = .x86_64;

pub fn build(b: *std.Build) void {
    const options = b.addOptions();
    setup(b, options);

    const  optimize = b.standardOptimizeOption(.{ });
    _ = setupKyber(b, options, optimize);
    _= setupLogos(b, options, optimize);

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
  };
    const qemu_cmd = b.addSystemCommand(&qemu_args);
    qemu_cmd.step.dependOn(b.getInstallStep());

    const run_qemu_cmd = b.step("run", "Run QEMU");
    run_qemu_cmd.dependOn(&qemu_cmd.step);
}


fn setup(b: *std.Build, options: *std.Build.Step.Options) void {
    const s_log_level = b.option([]const u8, "log_level", "log_level") orelse "info";

    const log_level: std.log.Level = b: {
        const eql = std.mem.eql;
        break :b if (eql(u8, s_log_level, "debug"))
            .debug
        else if (eql(u8, s_log_level, "info"))
            .info
        else if (eql(u8, s_log_level, "warn"))
            .warn
        else if (eql(u8, s_log_level, "error"))
            .err
        else
            @panic("Invalid log level");
    };

    options.addOption(std.log.Level, "log_level", log_level);
}

fn createArchModule(b: *std.Build, comptime arch: std.Target.Cpu.Arch) *std.Build.Module {
    const arch_path = switch (arch) {
        .x86_64 => "common/arch/x86_64.zig",
        else => @compileError("Unsupported architecture"),
    };
    return b.createModule(.{
        .root_source_file = b.path(arch_path),
    });
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
            .code_model = .kernel,
        }),
        .linkage = .static,
        .use_llvm = true,
    });
    kyber.entry = .{ .symbol_name = "_entry" };
    kyber.root_module.addOptions("option", options);
    kyber.root_module.addImport("arch", createArchModule(b, cpu_arch));
    b.installArtifact(kyber);

    const install_kyber = b.addInstallFile(
        kyber.getEmittedBin(),
        b.fmt("{s}/{s}", .{out_dir_name, kyber.name}),
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
                .os_tag =  .uefi,
            }),
            .optimize = optimize,
        }),
        .linkage = .static,
        .use_llvm = true,
    });
    logos.subsystem = .EfiApplication;
    logos.root_module.addOptions("option", options);
    logos.root_module.addImport("arch", createArchModule(b, cpu_arch));
    b.installArtifact(logos);

    const install_logos = b.addInstallFile(
        logos.getEmittedBin(),
        b.fmt("{s}/efi/boot/{s}", .{ out_dir_name, logos.name })
    );
    install_logos.step.dependOn(&logos.step);
    b.getInstallStep().dependOn(&install_logos.step);

    return logos;
}
