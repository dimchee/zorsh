const rl = @import("raylib");
const ecs = @import("ecs.zig");

pub const Transform = struct { position: rl.Vector2 };
pub const Health = struct { u32 };
pub const Direction = struct { rl.Vector2 };
pub const Gun = struct { lastFired: f64 };
pub const DeathTime = struct { f64 };
pub const WallTag = struct {};
pub const EnemyTag = struct {};
pub const BulletTag = struct {};
pub const PlayerTag = struct {};
pub const SpawnerTag = struct {};
pub const NextSpawn = struct { time: f64 };

pub const Circle = struct { radius: f32 };
pub const Square = struct { size: rl.Vector2 };

const EnemySpawner = .{ Transform, NextSpawn, SpawnerTag };
const Player = .{ Transform, Health, Gun, Circle, PlayerTag };
const Bullet = .{ Transform, DeathTime, Direction, Circle, BulletTag };
const Enemy = .{ Transform, Health, EnemyTag, Circle };
const Wall = .{ Transform, Square, WallTag };
// TODO different max_entities for different entities
pub const Ecs = ecs.Ecs(.{ Player, Bullet, Enemy, Wall, EnemySpawner });

// speeds is in units per frame, rate is in objects per second
pub const wall = .{ .height = 2.0, .size = 1.0 };
pub const character = .{ .radius = 0.5, .height = 2, .speed = 0.1 };
pub const bullet = .{ .radius = 0.1, .speed = 0.2, .damage = 10, .rate = 5.0, .lifetime = 2 };
pub const player = .{ .health = 100, .reward = 1, .cameraDelta = rl.Vector3.init(0, 10, 4) };
pub const enemy = .{ .speedFactor = 0.6, .spawnRate = 0.5, .health = 50, .damage = 2 };
pub const map =
    \\ [][][][][][][][][][][][][][][][][][][][][][][][][][]
    \\ []                                                []
    \\ []                zs                              []
    \\ []                                    []          []
    \\ [][]    [][][][][][][][][]  [][][][][][]          []
    \\ []           []                       []          []
    \\ []           []         zs            []          []
    \\ []           []                       []          []
    \\ [][]    [][][][][][][][]      [][][][][]          []
    \\ []                []                  []          []
    \\ []      ps        []                  []          []
    \\ []                []                  []          []
    \\ [][][][][]    [][][][][][][]    [][][][]          []
    \\ []                                    []          []
    \\ []                                                []
    \\ []                                                []
    \\ [][][][][][][][][][][][][][][][][][][][][][][][][][]
;
