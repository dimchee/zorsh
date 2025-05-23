const rl = @import("raylib");
const ecs = @import("ecs.zig");
const map = @import("map.zig");

pub const Transform = struct { position: rl.Vector2 };
pub const Physics = struct { velocity: rl.Vector2 };
pub const Health = struct { u32 };
pub const Gun = struct { lastFired: f64, angle: f32, triggered: bool };
pub const DeathTime = struct { f64 };
pub const EnemyTag = struct {};
pub const BulletTag = struct {};
pub const PlayerTag = struct {};
pub const SpawnerTag = struct {};
pub const NextSpawn = struct { time: f64 };

pub const Circle = struct { radius: f32 };
pub const Rectangle = struct { size: rl.Vector2 };

const EnemySpawner = .{ Transform, NextSpawn, SpawnerTag };
const Player = .{ Transform, Physics, Health, Gun, Circle, PlayerTag };
const Bullet = .{ Transform, Physics, DeathTime, Circle, BulletTag };
const Enemy = .{ Transform, Physics, Health, EnemyTag, Circle };
// TODO different max_entities for different entities
pub const Ecs = ecs.Ecs(.{ Player, Bullet, Enemy, EnemySpawner });
pub const Map = map.Map(@embedFile("map"));
pub const Cell = map.Cell;
pub const Position = map.Position;

// speeds is in units per frame, rate is in objects per second
pub const wall = .{ .height = 2.0, .size = 1.0 };
pub const character = .{ .radius = 0.5, .height = 2, .speed = 0.1 };
pub const bullet = .{ .radius = 0.1, .speed = 0.2, .damage = 10, .rate = 5.0, .lifetime = 2 };
pub const player = .{ .health = 100, .reward = 1, .cameraDelta = rl.Vector3.init(0, 10, 4) };
pub const enemy = .{ .speedFactor = 0.6, .spawnRate = 0.5, .health = 50, .damage = 2 };
