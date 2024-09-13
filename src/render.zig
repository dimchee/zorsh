const rl = @import("raylib");
const std = @import("std");
const ecslib = @import("ecs.zig");
const game = @import("game.zig");
const config = @import("config.zig");

fn cameraAt(position: rl.Vector2) rl.Camera3D {
    const pos3d = rl.Vector3.init(position.x, 0, position.y);
    return rl.Camera3D{
        .position = pos3d.add(config.player.cameraDelta),
        .target = pos3d,
        .up = rl.Vector3.init(0, 1, 0),
        .fovy = 60,
        .projection = rl.CameraProjection.camera_perspective,
    };
}

fn posToVec3(pos: config.Position, height: f32) rl.Vector3 {
    return rl.Vector3.init(@floatFromInt(pos.x), height, @floatFromInt(pos.y));
}

pub const Textures = struct { wall: rl.Material, tile: rl.Material };

pub fn load_textures() Textures {
    var wall = rl.loadTexture("assets/tiny_texture_pack_2/256x256/Brick/Brick_02-256x256.png");
    rl.genTextureMipmaps(&wall);
    var wallMat = rl.loadMaterialDefault();
    rl.setTextureFilter(wall, rl.TextureFilter.texture_filter_bilinear);
    rl.setMaterialTexture(&wallMat, rl.MaterialMapIndex.material_map_albedo, wall);
    var tile = rl.loadTexture("assets/tiny_texture_pack_2/256x256/Tile/Tile_17-256x256.png");
    rl.genTextureMipmaps(&tile);
    var tileMat = rl.loadMaterialDefault();
    rl.setTextureFilter(tile, rl.TextureFilter.texture_filter_bilinear);
    rl.setMaterialTexture(&tileMat, rl.MaterialMapIndex.material_map_albedo, tile);
    return .{ .wall = wallMat, .tile = tileMat };
}
pub fn draw(ecs: *config.Ecs, textures: *Textures) void {
    const camera = camera: {
        var q = ecs.query(struct { transform: config.Transform, tag: config.PlayerTag });
        var it = q.iterator();
        const player = it.next().?;
        std.debug.assert(it.next() == null);
        break :camera cameraAt(player.transform.position);
    };
    camera.begin();
    defer camera.end();
    const cube = rl.genMeshCube(config.wall.size, config.wall.height, config.wall.size);
    const plane = rl.genMeshPlane(config.wall.size, config.wall.size, 1, 1);
    {
        for (config.Map.items, 0..) |cell, ind| {
            const pos = config.Map.toPos(ind).?;
            switch (cell) {
                .Wall => {
                    // const size = rl.Vector3.init(config.wall.size, config.wall.height, config.wall.size);
                    // rl.drawCubeV(posToVec3(pos, 1), size, rl.Color.dark_blue);
                    cube.draw(textures.wall, rl.math.matrixTranslate(@floatFromInt(pos.x), 1, @floatFromInt(pos.y)));
                },
                else => {
                    // rl.drawPlane(posToVec3(pos, 0), rl.Vector2.init(1, 1), if ((pos.x + pos.y) % 2 == 0) rl.Color.white else rl.Color.blue),
                    plane.draw(textures.tile, rl.math.matrixTranslate(@floatFromInt(pos.x), 0, @floatFromInt(pos.y)));
                },
            }
        }
    }
    {
        var q = ecs.query(struct { transform: config.Transform, tag: config.PlayerTag });
        var it = q.iterator();
        while (it.next()) |player| {
            const start = rl.Vector3.init(player.transform.position.x, config.character.radius, player.transform.position.y);
            const end = rl.Vector3.init(player.transform.position.x, config.character.height - config.character.radius, player.transform.position.y);
            rl.drawCapsule(start, end, config.character.radius, 10, 1, rl.Color.light_gray);
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
