#!/bin/bash

# Supabase Docker management script

DOCKER_DIR="docker"

show_help() {
    echo "🚀 Supabase Docker management script"
    echo "=========================="
    echo ""
    echo "Usage: ./supabase-manage.sh [command]"
    echo ""
    echo "Commands:"
    echo "  start       - Start all services"
    echo "  stop        - Stop all services"
    echo "  restart     - Restart all services"
    echo "  status      - View service status"
    echo "  logs        - View logs for all services"
    echo "  logs [service] - View logs for the specified service"
    echo "  clean       - Stop and remove all containers and volumes (⚠️ this will delete data)"
    echo "  reset       - Fully reset (stop, clean up, restart)"
    echo "  help        - Show this help information"
    echo ""
    echo "Examples:"
    echo "  ./supabase-manage.sh start"
    echo "  ./supabase-manage.sh logs studio"
    echo "  ./supabase-manage.sh status"
}

start_services() {
    echo "🚀 Starting Supabase services..."
    cd "$DOCKER_DIR"
    docker compose up -d
    echo ""
    echo "✅ Services started"
    echo ""
    echo "🌐 Access URLs:"
    echo "   - Supabase Studio: http://localhost:3000"
    echo "   - API Gateway:      http://localhost:8000"
    echo "   - Database:         localhost:5432"
    echo "   - Analytics:        http://localhost:4000"
}

stop_services() {
    echo "🛑 Stopping Supabase services..."
    cd "$DOCKER_DIR"
    docker compose down
    echo "✅ Services stopped"
}

restart_services() {
    echo "🔄 Restarting Supabase services..."
    cd "$DOCKER_DIR"
    docker compose restart
    echo "✅ Services restarted"
}

show_status() {
    echo "📊 Supabase service status"
    echo "===================="
    echo ""
    cd "$DOCKER_DIR"
    docker compose ps
}

show_logs() {
    cd "$DOCKER_DIR"
    if [ -z "$1" ]; then
        echo "📚 Viewing logs for all services (Ctrl+C to exit)..."
        docker compose logs -f
    else
        echo "📚 Viewing logs for the $1 service (Ctrl+C to exit)..."
        docker compose logs -f "$1"
    fi
}

clean_all() {
    echo "⚠️  Warning: this will delete all containers and data volumes!"
    read -p "Are you sure you want to continue? (yes/no) " -r
    echo ""
    if [[ $REPLY == "yes" ]]; then
        echo "🧹 Cleaning up all containers and data..."
        cd "$DOCKER_DIR"
        docker compose down -v --remove-orphans
        echo "✅ Cleanup complete"
    else
        echo "Cancelled"
    fi
}

reset_all() {
    echo "🔄 Fully resetting Supabase..."
    clean_all
    if [[ $REPLY == "yes" ]]; then
        echo ""
        start_services
    fi
}

# Main logic
case "$1" in
    start)
        start_services
        ;;
    stop)
        stop_services
        ;;
    restart)
        restart_services
        ;;
    status)
        show_status
        ;;
    logs)
        show_logs "$2"
        ;;
    clean)
        clean_all
        ;;
    reset)
        reset_all
        ;;
    help|--help|-h|"")
        show_help
        ;;
    *)
        echo "❌ Unknown command: $1"
        echo ""
        show_help
        exit 1
        ;;
esac
