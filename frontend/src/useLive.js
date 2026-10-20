import { useEffect, useRef, useState } from 'react';
/**
 * Native WebSocket with exponential backoff. On every (re)connect the caller
 * reloads a REST snapshot, so missed events are reconciled from MongoDB.
 */
export function useLive(projectId, onEvent, onConnected) {
    const [state, setState] = useState('connecting');
    const handlers = useRef({ onEvent, onConnected });
    handlers.current = { onEvent, onConnected };
    useEffect(() => {
        if (!projectId)
            return;
        let socket;
        let timer;
        let attempt = 0;
        let closed = false;
        const connect = () => {
            const scheme = location.protocol === 'https:' ? 'wss' : 'ws';
            socket = new WebSocket(`${scheme}://${location.host}/ws/v1/live?project_id=${encodeURIComponent(projectId)}`);
            socket.onmessage = (message) => {
                const data = JSON.parse(String(message.data));
                if (data.type === 'hello') {
                    attempt = 0;
                    setState('live');
                    handlers.current.onConnected();
                }
                else {
                    handlers.current.onEvent(data);
                }
            };
            socket.onclose = () => {
                if (closed)
                    return;
                attempt += 1;
                setState(attempt > 6 ? 'offline' : 'reconnecting');
                timer = window.setTimeout(connect, Math.min(30_000, 1000 * 2 ** (attempt - 1)));
            };
        };
        connect();
        return () => {
            closed = true;
            window.clearTimeout(timer);
            socket?.close();
        };
    }, [projectId]);
    return state;
}
