#!/bin/bash

echo "🔍 Monitoreo en tiempo real de LiveWalls"
echo "========================================"
echo "📱 App PID: $(pgrep LiveWalls || echo 'No running')"
echo "📄 Log file: ~/Documents/LiveWalls_debug.log"
echo ""

# Función para mostrar memoria
show_memory() {
    local pid=$(pgrep LiveWalls)
    if [ ! -z "$pid" ]; then
        local memory=$(ps -o rss= -p $pid | tr -d ' ')
        echo "🧠 Memory: ${memory} KB"
    else
        echo "❌ App not running"
    fi
}

# Función para mostrar logs recientes
show_recent_logs() {
    if [ -f ~/Documents/LiveWalls_debug.log ]; then
        local lines=$(wc -l < ~/Documents/LiveWalls_debug.log)
        echo "📄 Log lines: $lines"
        if [ $lines -gt 0 ]; then
            echo "   Last log:"
            tail -1 ~/Documents/LiveWalls_debug.log | sed 's/^/   /'
        fi
    else
        echo "📄 No debug log yet"
    fi
}

echo "🎯 Instrucciones:"
echo "   1. Abre LiveWalls desde la barra de menú"
echo "   2. Haz clic en 'Vista Previa Video'"
echo "   3. Observa los logs aparecer aquí"
echo ""

# Monitoreo continuo
counter=1
while true; do
    echo "🔄 Check #$counter ($(date +"%H:%M:%S"))"
    show_memory
    show_recent_logs
    
    # Verificar si la app crashed
    if ! pgrep LiveWalls > /dev/null; then
        echo "💥 CRASH DETECTADO!"
        echo "📋 Últimos logs del sistema:"
        log show --predicate 'process == "LiveWalls"' --last 1m --style compact | tail -5
        break
    fi
    
    echo "---"
    sleep 5
    counter=$((counter + 1))
done
