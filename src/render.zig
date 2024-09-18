const rl = @import("raylib");
const std = @import("std");
const ecslib = @import("ecs.zig");
const game = @import("game.zig");
const config = @import("config.zig");

fn posToVec3(pos: config.Position, height: f32) rl.Vector3 {
    return rl.Vector3.init(@floatFromInt(pos.x), height, @floatFromInt(pos.y));
}
fn vec2ToVec3(pos: rl.Vector2, height: f32) rl.Vector3 {
    return rl.Vector3.init(pos.x, height, pos.y);
}

// TODO mesh generation in zig
pub const Data = struct {
    shader: rl.Shader,
    wall: rl.Model,
    tile: rl.Model,
    character: rl.Model,
    bullet: rl.Model,
    lastChangedFs: i128,
    lastChangedVs: i128,
    fn updateShader(self: *@This()) void {
        const statsFs = std.fs.cwd().statFile("assets/base.fs") catch unreachable;
        const statsVs = std.fs.cwd().statFile("assets/base.vs") catch unreachable;
        if (statsFs.mtime > self.lastChangedFs or statsVs.mtime > self.lastChangedVs) {
            self.lastChangedFs = statsFs.mtime;
            self.lastChangedVs = statsVs.mtime;
            rl.unloadShader(self.shader);
            self.shader = rl.loadShader("assets/base.vs", "assets/base.fs");
            inline for (std.meta.fields(@This())) |field| if (field.type == rl.Model) {
                @field(self, field.name).materials[0].shader = self.shader;
            };
        }
    }
    fn setUniform(self: *@This(), comptime location: [*:0]const u8, value: anytype) void {
        rl.setShaderValue(
            self.shader,
            rl.getShaderLocation(self.shader, location),
            &value,
            if (@TypeOf(value) == rl.Vector3)
                rl.ShaderUniformDataType.shader_uniform_vec3
            else if (@TypeOf(value) == rl.Color)
                rl.ShaderUniformDataType.shader_uniform_vec4
            else
                @compileError("Uniform type not recognised"),
        );
    }
    fn loadTexture(value: anytype) rl.Texture {
        if (@TypeOf(value) == rl.Color) {
            const color = rl.genImageColor(1, 1, value);
            defer color.unload();
            return rl.loadTextureFromImage(color);
        } else {
            var texture = rl.loadTexture(value);
            rl.genTextureMipmaps(&texture);
            rl.setTextureFilter(texture, rl.TextureFilter.texture_filter_bilinear);
            return texture;
        }
    }
    fn loadModel(shader: rl.Shader, texture: anytype, mesh: rl.Mesh) rl.Model {
        var model = rl.Model.fromMesh(mesh);
        if (@as(?*rl.Material, &model.materials[0])) |mat| {
            const tex = Data.loadTexture(texture);
            mat.shader = shader;
            rl.setMaterialTexture(mat, rl.MaterialMapIndex.material_map_albedo, tex);
        }
        return model;
    }
    pub fn init() Data {
        const shader = rl.loadShader("assets/base.vs", "assets/base.fs");

        return .{
            .shader = shader,
            .wall = Data.loadModel(
                shader,
                "assets/tiny_texture_pack_2/256x256/Brick/Brick_02-256x256.png",
                rl.genMeshCube(config.wall.size, config.wall.height, config.wall.size),
            ),
            .tile = Data.loadModel(
                shader,
                "assets/tiny_texture_pack_2/256x256/Tile/Tile_17-256x256.png",
                rl.genMeshPlane(config.wall.size, config.wall.size, 1, 1),
            ),
            .character = Data.loadModel(
                shader,
                rl.Color.white,
                rl.genMeshCylinder(config.character.radius, config.character.height, 10),
            ),
            .bullet = Data.loadModel(
                shader,
                rl.Color.blue,
                rl.genMeshSphere(config.bullet.radius, 10, 10),
            ),
            .lastChangedFs = 0,
            .lastChangedVs = 0,
        };
    }
};

pub fn draw(ecs: *config.Ecs, data: *Data) void {
    data.updateShader();
    const camera = camera: {
        var q = ecs.query(struct { transform: config.Transform, tag: config.PlayerTag });
        var it = q.iterator();
        const player = it.next().?;
        std.debug.assert(it.next() == null);
        const pos3d = vec2ToVec3(player.transform.position, 0);
        const cameraPos = pos3d.add(config.player.cameraDelta);
        const lightPos = pos3d.add(rl.Vector3.init(0, 1, 1));
        data.setUniform("lightPos", lightPos);
        data.setUniform("viewPos", cameraPos);
        break :camera rl.Camera3D{
            .position = cameraPos,
            .target = pos3d,
            .up = rl.Vector3.init(0, 1, 0),
            .fovy = 60,
            .projection = rl.CameraProjection.camera_perspective,
        };
    };
    camera.begin();
    defer camera.end();

    {
        for (config.Map.items, 0..) |cell, ind| {
            const pos = config.Map.toPos(ind).?;
            switch (cell) {
                .Wall => data.wall.draw(posToVec3(pos, 1), 1.0, rl.Color.white),
                else => data.tile.draw(posToVec3(pos, 0), 1.0, rl.Color.white),
            }
        }
    }
    {
        var q = ecs.query(struct { transform: config.Transform, tag: config.PlayerTag });
        var it = q.iterator();
        while (it.next()) |player|
            data.character.draw(vec2ToVec3(player.transform.position, 0), 1.0, rl.Color.white);
    }
    {
        var q = ecs.query(struct { transform: config.Transform, tag: config.BulletTag });
        var it = q.iterator();
        while (it.next()) |bullet|
            data.bullet.draw(vec2ToVec3(bullet.transform.position, 1.2), 1.0, rl.Color.white);
    }
    {
        var q = ecs.query(struct { transform: config.Transform, health: config.Health, tag: config.EnemyTag });
        var it = q.iterator();
        while (it.next()) |enemy| {
            const hp = @as(f32, @floatFromInt(enemy.health[0])) / config.enemy.health;
            const color = rl.Color.fromNormalized(rl.Vector4.init(hp, 0, 0.2, 1));

            data.setUniform("colDiffuse", color);
            data.character.draw(vec2ToVec3(enemy.transform.position, 0), 1.0, color);
            data.setUniform("colDiffuse", rl.Color.white);
        }
    }
}
