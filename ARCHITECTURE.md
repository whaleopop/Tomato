# 🏗️ Архитектура проекта ROYALTIM-3

## Обзор

Проект использует **Component-Based Architecture** (аналог ECS) для обеспечения модульности и масштабируемости.

## Основные системы

### 1. Component System (core/components/)

Все игровые сущности состоят из компонентов:

- **Component.gd** - базовый класс для всех компонентов
- **MovementComponent.gd** - управление движением
- **HealthComponent.gd** - здоровье и урон
- **CombatComponent.gd** - боевая система
- **AbilityComponent.gd** - система способностей
- **InventoryComponent.gd** - инвентарь
- **NetworkingComponent.gd** - сетевая синхронизация

### 2. Entity System (core/entities/)

- **Entity.gd** - базовая сущность, содержащая компоненты
- **Player.gd** - игрок с полным набором компонентов

### 3. Character System (characters/data/)

Каждый персонаж определяется через ресурс `CharacterData`:
- Базовые характеристики (здоровье, скорость)
- Активная способность
- Пассивная способность
- Путь к 3D модели

### 4. Ability System (abilities/)

#### Активные способности (abilities/active/)
- Наследуются от `ActiveAbility`
- Имеют кулдаун и длительность
- Активируются игроком

#### Пассивные способности (abilities/passive/)
- Наследуются от `PassiveAbility`
- Работают постоянно
- Применяются автоматически

### 5. World Generation (world/generation/)

- **HexGenerator.gd** - генерирует гексагональную сетку
- **HexGrid.gd** - управляет сеткой тайлов
- **HexTile.gd** - отдельный гексагональный тайл
- **MapGenerator.gd** - главный генератор карты

### 6. Destruction System (world/destruction/)

- **DestructionSystem.gd** - управляет разрушением карты
- **TileDestroyer.gd** - разрушает отдельные тайлы
- Заменяет классическую "зону" в battle royale

### 7. Network System (network/)

#### Сервер (network/server/)
- **GameServer.gd** - главный сервер
- **ServerWorld.gd** - серверный мир
- **ServerPlayer.gd** - серверное представление игрока
- **TickSystem.gd** - система тиков для синхронизации

#### Клиент (network/client/)
- **GameClient.gd** - главный клиент
- **ClientWorld.gd** - клиентский мир
- **ClientPlayer.gd** - клиентское представление игрока

### 8. Inventory System (inventory/)

- **Inventory.gd** - контейнер для предметов
- **ItemStack.gd** - стек предметов
- **items/** - типы предметов (оружие, аптечки, перки)
- **loot/** - генерация лута

### 9. UI System (ui/)

- **hud/** - элементы HUD (здоровье, способности, миникарта)
- **menus/** - меню (главное, выбор персонажа, инвентарь, пауза)

## Поток данных

### Серверная авторитетность

1. Клиент отправляет ввод на сервер
2. Сервер обрабатывает ввод и обновляет состояние
3. Сервер отправляет обновленное состояние всем клиентам
4. Клиенты интерполируют состояние для плавности

### Синхронизация

- **TickSystem** работает на частоте 20 тиков/сек
- **SyncManager** синхронизирует состояние 10 раз/сек
- Используется ENet Multiplayer API

## Расширение проекта

### Добавление нового персонажа

1. Создайте файл в `characters/data/`:
```gdscript
extends CharacterData
class_name NewCharacter

func _init():
    character_name = "New Character"
    base_health = 100.0
    base_speed = 5.0
    # ... настройка способностей
```

### Добавление новой способности

1. Создайте класс в `abilities/active/` или `abilities/passive/`:
```gdscript
extends ActiveAbility
class_name NewAbility

func _init():
    super._init("New Ability", 5.0)
    duration = 1.0

func _on_activate(entity: Entity, target_position: Vector3) -> bool:
    # Логика способности
    return true
```

### Добавление нового предмета

1. Создайте класс в `inventory/items/`:
```gdscript
extends ItemData
class_name NewItem

func _init():
    super._init()
    item_name = "New Item"
    consumable = true
```

## Оптимизация

- **LOD** для 3D моделей
- **Instancing** для повторяющихся объектов
- **Object pooling** для пуль и эффектов
- **Baking lighting** для статической карты

## Тестирование

Тесты находятся в `tests/`:
- `test_components.gd` - тесты компонентов
- `test_inventory.gd` - тесты инвентаря
- `test_abilities.gd` - тесты способностей
- `test_hex_grid.gd` - тесты гексагональной сетки

Запуск через GUT (Godot Unit Testing).

