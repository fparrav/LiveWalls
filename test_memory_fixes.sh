#!/bin/bash

# Test script para verificar las correcciones de memory management en VideoPlayerView
# Este script simula el uso intensivo de la aplicación para verificar que no haya crashes

echo "🧪 Iniciando pruebas de memory management fixes..."
echo "📱 App PID: $(pgrep LiveWalls)"

# Verificar que la app esté ejecutándose
if ! pgrep LiveWalls > /dev/null; then
    echo "❌ LiveWalls no está ejecutándose. Lanzando aplicación..."
    open build/Debug/LiveWalls.app
    sleep 3
fi

echo "✅ LiveWalls está ejecutándose con PID: $(pgrep LiveWalls)"

# Verificar archivos de video disponibles
echo "📹 Videos disponibles para testing:"
ls -la /Users/felipe/Livewall/*.mp4 | head -5

# Función para verificar si la app sigue viva
check_app_status() {
    if ! pgrep LiveWalls > /dev/null; then
        echo "💥 CRASH DETECTADO: La aplicación se cerró inesperadamente!"
        echo "📋 Últimos logs del sistema:"
        log show --predicate 'process == "LiveWalls"' --last 2m --style compact | tail -10
        exit 1
    else
        echo "✅ App sigue funcionando correctamente - PID: $(pgrep LiveWalls)"
    fi
}

# Función para verificar memory usage
check_memory() {
    local pid=$(pgrep LiveWalls)
    if [ ! -z "$pid" ]; then
        local memory=$(ps -o rss= -p $pid)
        echo "🧠 Memory usage: ${memory} KB"
        
        # Alert si el uso de memoria es muy alto (más de 500MB)
        if [ $memory -gt 512000 ]; then
            echo "⚠️  WARNING: High memory usage detected: ${memory} KB"
        fi
    fi
}

echo ""
echo "🔄 INICIO DE TESTING DE MEMORY MANAGEMENT"
echo "========================================="

# Test 1: Verificar estado inicial
echo "📋 Test 1: Estado inicial de la aplicación"
check_app_status
check_memory
sleep 2

# Test 2: Verificar logs de debugging (solo si existen)
echo ""
echo "📋 Test 2: Verificando logs de debugging"
if [ -f ~/Documents/LiveWalls_debug.log ]; then
    echo "📄 Últimas entradas del log de debugging:"
    tail -5 ~/Documents/LiveWalls_debug.log
else
    echo "📄 Log de debugging aún no existe (esperado si no se ha activado VideoPlayerView)"
fi

# Test 3: Simular presión de memoria usando menú de la app
echo ""
echo "📋 Test 3: Testing del menú bar y ventana principal"
echo "👆 Por favor:"
echo "   1. Haz clic en el ícono de LiveWalls en la barra de menú"
echo "   2. Selecciona 'Abrir Configuración'"
echo "   3. Haz clic en 'Vista Previa Video' para activar VideoPlayerView"
echo "   4. Espera 10 segundos y presiona Enter aquí para continuar..."

read -p "Presiona Enter cuando hayas completado los pasos anteriores..."

# Verificar estado después de activar VideoPlayerView
echo ""
echo "📋 Verificando estado después de activar VideoPlayerView..."
check_app_status
check_memory

# Test 4: Verificar logs después de activación
echo ""
echo "📋 Test 4: Verificando logs después de activar VideoPlayerView"
if [ -f ~/Documents/LiveWalls_debug.log ]; then
    echo "📄 Log entries (últimas 10 líneas):"
    tail -10 ~/Documents/LiveWalls_debug.log
    echo ""
    echo "📊 Número total de log entries:"
    wc -l ~/Documents/LiveWalls_debug.log
else
    echo "⚠️  Log de debugging no encontrado - VideoPlayerView no se ha activado aún"
fi

# Test 5: Monitoreo continuo durante 30 segundos
echo ""
echo "📋 Test 5: Monitoreo continuo por 30 segundos..."
echo "🎯 Durante este tiempo, puedes cambiar videos o cerrar/abrir la ventana"

for i in {1..6}; do
    echo "⏱️  Monitoring cycle $i/6..."
    check_app_status
    check_memory
    
    # Verificar por nuevos logs
    if [ -f ~/Documents/LiveWalls_debug.log ]; then
        local log_lines=$(wc -l < ~/Documents/LiveWalls_debug.log)
        echo "📄 Log entries: $log_lines"
    fi
    
    sleep 5
done

# Test 6: Verificar logs finales
echo ""
echo "📋 Test 6: Análisis final de logs"
if [ -f ~/Documents/LiveWalls_debug.log ]; then
    echo "📄 Análisis del log de debugging:"
    echo "   - Total líneas: $(wc -l < ~/Documents/LiveWalls_debug.log)"
    echo "   - Entradas de deinit: $(grep -c "deinit" ~/Documents/LiveWalls_debug.log || echo "0")"
    echo "   - Entradas de cleanup: $(grep -c "cleanup" ~/Documents/LiveWalls_debug.log || echo "0")"
    echo "   - Entradas de emergency: $(grep -c "emergency" ~/Documents/LiveWalls_debug.log || echo "0")"
    echo ""
    echo "📄 Últimas 15 líneas del log:"
    tail -15 ~/Documents/LiveWalls_debug.log
else
    echo "⚠️  No se generó log de debugging - VideoPlayerView no fue activado"
fi

# Resultado final
echo ""
echo "🏁 RESULTADO DEL TEST"
echo "===================="
check_app_status
check_memory

if pgrep LiveWalls > /dev/null; then
    echo "✅ SUCCESS: La aplicación sobrevivió todas las pruebas!"
    echo "🎉 Las correcciones de memory management parecen estar funcionando correctamente"
else
    echo "❌ FAILURE: La aplicación crashed durante las pruebas"
    echo "🔧 Las correcciones de memory management necesitan más trabajo"
fi

echo ""
echo "📋 Para testing adicional:"
echo "   - Ejecuta: ./realtime_status.sh para monitoreo continuo"
echo "   - Revisa: ~/Documents/LiveWalls_debug.log para logs detallados"
echo "   - Usa: Console.app para ver todos los logs del sistema"

echo ""
echo "🧪 Test completado. App PID actual: $(pgrep LiveWalls || echo 'No running')"
