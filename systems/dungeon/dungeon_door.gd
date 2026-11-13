class_name DungeonDoor
extends RefCounted

enum State {
	FREE, ## jeszcze nie przypisane
	LINKED, ## połączone korytarzem z innym pokojem
	WFC, ## wolne wejście pod generator WFC
}

## Pozycja na siatce (świat / map space).
var cell: Vector2i = Vector2i.ZERO
## Outward normal w przestrzeni mapy (np. (1,0) = wschód).
var outward: Vector2i = Vector2i.RIGHT
var state: State = State.FREE
## Indeks pokoju-właściciela w DungeonData.rooms.
var room_index: int = -1
## Połączenie (gdy LINKED).
var link_room_index: int = -1
var link_door_index: int = -1
