const rl = @import("raylib");
const std = @import("std");
const ecslib = @import("ecs.zig");
const game = @import("game.zig");
const config = @import("config.zig");

fn posToVec3(pos: config.Position, height: f32) rl.Vector3 {
    return rl.Vector3.init(@floatFromInt(pos.x), height, @floatFromInt(pos.y));
}

pub const Data = struct {
    wallMaterial: rl.Material,
    tileMaterial: rl.Material,
    characterMaterial: rl.Material,
    cubeMesh: rl.Mesh,
    planeMesh: rl.Mesh,
    capsuleMesh: rl.Mesh,
    lastChangedFs: i128,
    lastChangedVs: i128,
};

pub fn load() Data {
    const shader = rl.loadShader("assets/base.vs", "assets/base.fs");

    var wall = rl.loadTexture("assets/tiny_texture_pack_2/256x256/Brick/Brick_02-256x256.png");
    rl.genTextureMipmaps(&wall);
    var wallMat = rl.loadMaterialDefault();
    wallMat.shader = shader;
    rl.setTextureFilter(wall, rl.TextureFilter.texture_filter_bilinear);
    rl.setMaterialTexture(&wallMat, rl.MaterialMapIndex.material_map_albedo, wall);

    var tile = rl.loadTexture("assets/tiny_texture_pack_2/256x256/Tile/Tile_17-256x256.png");
    rl.genTextureMipmaps(&tile);
    var tileMat = rl.loadMaterialDefault();
    tileMat.shader = shader;
    rl.setTextureFilter(tile, rl.TextureFilter.texture_filter_bilinear);
    rl.setMaterialTexture(&tileMat, rl.MaterialMapIndex.material_map_albedo, tile);

    var characterMaterial = rl.loadMaterialDefault();
    characterMaterial.shader = shader;
    rl.setMaterialTexture(&characterMaterial, rl.MaterialMapIndex.material_map_albedo, wall);
    return .{
        .wallMaterial = wallMat,
        .tileMaterial = tileMat,
        .characterMaterial = characterMaterial,
        .cubeMesh = rl.genMeshCube(config.wall.size, config.wall.height, config.wall.size),
        .planeMesh = rl.genMeshCube(config.wall.size, 0.01, config.wall.size),
        // rl.genMeshPlane(config.wall.size, config.wall.size, 1, 1),
        .capsuleMesh = rl.genMeshCylinder(config.character.radius, config.character.height, 10),
        .lastChangedFs = 0,
        .lastChangedVs = 0,
    };
}
pub fn draw(ecs: *config.Ecs, data: *Data) void {
    {
        const statsFs = std.fs.cwd().statFile("assets/base.fs") catch unreachable;
        const statsVs = std.fs.cwd().statFile("assets/base.vs") catch unreachable;
        if (statsFs.mtime > data.lastChangedFs or statsVs.mtime > data.lastChangedVs) {
            data.lastChangedFs = statsFs.mtime;
            data.lastChangedVs = statsVs.mtime;
            rl.unloadShader(data.wallMaterial.shader);
            data.wallMaterial.shader = rl.loadShader("assets/base.vs", "assets/base.fs");
        }
    }
    const camera = camera: {
        var q = ecs.query(struct { transform: config.Transform, tag: config.PlayerTag });
        var it = q.iterator();
        const player = it.next().?;
        std.debug.assert(it.next() == null);
        const pos3d = rl.Vector3.init(player.transform.position.x, 0, player.transform.position.y);
        const cameraPos = pos3d.add(config.player.cameraDelta);
        const lightPos = pos3d.add(rl.Vector3.init(0, 1, 1));
        rl.setShaderValue(
            data.wallMaterial.shader,
            rl.getShaderLocation(data.wallMaterial.shader, "lightPos"),
            &lightPos,
            rl.ShaderUniformDataType.shader_uniform_vec3,
        );
        rl.setShaderValue(
            data.wallMaterial.shader,
            rl.getShaderLocation(data.wallMaterial.shader, "viewPos"),
            &cameraPos,
            rl.ShaderUniformDataType.shader_uniform_vec3,
        );
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
                .Wall => {
                    // const size = rl.Vector3.init(config.wall.size, config.wall.height, config.wall.size);
                    // rl.drawCubeV(posToVec3(pos, 1), size, rl.Color.dark_blue);
                    data.cubeMesh.draw(data.wallMaterial, rl.math.matrixTranslate(@floatFromInt(pos.x), 1, @floatFromInt(pos.y)));
                },
                else => {
                    // rl.drawPlane(posToVec3(pos, 0), rl.Vector2.init(1, 1), if ((pos.x + pos.y) % 2 == 0) rl.Color.white else rl.Color.blue),
                    data.planeMesh.draw(data.wallMaterial, rl.math.matrixTranslate(@floatFromInt(pos.x), 0, @floatFromInt(pos.y)));
                },
            }
        }
    }
    {
        var q = ecs.query(struct { transform: config.Transform, tag: config.PlayerTag });
        var it = q.iterator();
        while (it.next()) |player| {
            // const start = rl.Vector3.init(player.transform.position.x, config.character.radius, player.transform.position.y);
            // const end = rl.Vector3.init(player.transform.position.x, config.character.height - config.character.radius, player.transform.position.y);
            const pos = rl.Vector3.init(player.transform.position.x, 0, player.transform.position.y);
            data.capsuleMesh.draw(data.wallMaterial, rl.math.matrixTranslate(pos.x, pos.y, pos.z));
            // rl.drawCapsule(start, end, config.character.radius, 10, 1, rl.Color.light_gray);
        }
    }
    {
        var q = ecs.query(struct { transform: config.Transform, tag: config.BulletTag });
        var it = q.iterator();
        while (it.next()) |bullet| {
            const pos = rl.Vector3.init(bullet.transform.position.x, 1.2, bullet.transform.position.y);
            rl.drawSphere(pos, config.bullet.radius, rl.Color.white);
        }
    }
    {
        var q = ecs.query(struct { transform: config.Transform, health: config.Health, tag: config.EnemyTag });
        var it = q.iterator();
        while (it.next()) |enemy| {
            const start = rl.Vector3.init(enemy.transform.position.x, config.character.radius, enemy.transform.position.y);
            const end = rl.Vector3.init(enemy.transform.position.x, config.character.height - config.character.radius, enemy.transform.position.y);
            const color = rl.Color.fromNormalized(rl.Vector4.init(@as(f32, @floatFromInt(enemy.health[0])) / config.enemy.health, 0, 0.2, 1));
            rl.drawCapsule(start, end, config.character.radius, 10, 1, color);
        }
    }
    // Debug collisions
    // {
    //     for (self.xs.items, self.ys.items) |x, y| {
    //         const pos = rl.Vector3.init((x.min + x.max) / 2, 1, (y.min + y.max) / 2);
    //         const size = rl.Vector3.init(x.max - x.min, 0.1, y.max - y.min);
    //         rl.drawCubeV(pos, size, rl.Color.red);
    //     }
    //     const coll = collision.collisions(self.allocator, .{ self.xs.items, self.ys.items }) catch unreachable();
    //     for (coll.items) |c| {
    //         {
    //             const x = self.xs.items[c[0]];
    //             const y = self.ys.items[c[0]];
    //             const pos = rl.Vector3.init((x.min + x.max) / 2, 1.5, (y.min + y.max) / 2);
    //             const size = rl.Vector3.init(x.max - x.min, 0.1, y.max - y.min);
    //             rl.drawCubeV(pos, size, rl.Color.yellow);
    //         }
    //         {
    //             const x = self.xs.items[c[1]];
    //             const y = self.ys.items[c[1]];
    //             const pos = rl.Vector3.init((x.min + x.max) / 2, 1.5, (y.min + y.max) / 2);
    //             const size = rl.Vector3.init(x.max - x.min, 0.1, y.max - y.min);
    //             rl.drawCubeV(pos, size, rl.Color.yellow);
    //         }
    //     }
    // }
}
