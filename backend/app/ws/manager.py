from fastapi import WebSocket


class ConnectionManager:
    """Manages active WebSocket connections."""

    def __init__(self) -> None:
        self.active_connections: dict[str, WebSocket] = {}

    async def connect(self, websocket: WebSocket, user_id: str) -> None:
        """Accept WebSocket connection and store it."""
        await websocket.accept()
        # Close existing connection if user reconnects
        if user_id in self.active_connections:
            try:
                await self.active_connections[user_id].close()
            except Exception:
                pass
        self.active_connections[user_id] = websocket

    def disconnect(self, user_id: str) -> None:
        """Remove connection from active connections."""
        self.active_connections.pop(user_id, None)

    async def send_to_user(self, user_id: str, message: dict) -> None:
        """Send JSON message to a specific user."""
        websocket = self.active_connections.get(user_id)
        if websocket:
            try:
                await websocket.send_json(message)
            except Exception:
                # Connection may have been closed
                self.disconnect(user_id)

    async def broadcast_to_users(self, user_ids: list[str], message: dict) -> None:
        """Send JSON message to multiple users."""
        for user_id in user_ids:
            await self.send_to_user(user_id, message)


# Singleton instance
manager = ConnectionManager()
