const std = @import("std");
const engine = @import("../engine.zig");
const gl = @import("gl");

gl_procs: gl.ProcTable,
viewport_size: engine.Size,
