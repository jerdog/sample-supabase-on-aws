#!/bin/bash

# Supabase Studio build and start script
# Used to build the custom Studio image and start all services

set -e  # Exit immediately on error

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DOCKER_DIR="docker"
STUDIO_IMAGE="supabase-studio-local:latest"
DOCKERFILE_PATH="apps/studio/Dockerfile"

# Print colored messages
print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_header() {
    echo ""
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================${NC}"
    echo ""
}

# Show help information
show_help() {
    cat << EOF
🚀 Supabase Studio build and start script

Usage: ./build-and-start.sh [options]

Options:
  --build-only        Only build the image, do not start services
  --no-cache          Build without using cache (full rebuild)
  --skip-build        Skip the build and start services directly
  --stop              Stop all services
  --restart           Restart all services
  --status            View service status
  --logs [service]    View logs (view all logs if no service is specified)
  --clean             Stop services and clean up containers and volumes
  --help, -h          Show this help information

Examples:
  ./build-and-start.sh                    # Build the image and start services
  ./build-and-start.sh --build-only       # Only build the image
  ./build-and-start.sh --no-cache         # Full rebuild and start
  ./build-and-start.sh --skip-build       # Skip the build and start directly
  ./build-and-start.sh --logs studio      # View logs for the studio service
  ./build-and-start.sh --stop             # Stop all services

EOF
}

# Check whether Docker is running
check_docker() {
    print_info "Checking Docker environment..."
    if ! docker info > /dev/null 2>&1; then
        print_error "Docker is not running, please start Docker first"
        exit 1
    fi
    print_success "Docker is running normally"
}

# Check required files
check_files() {
    print_info "Checking required files..."

    if [ ! -f "$DOCKERFILE_PATH" ]; then
        print_error "Dockerfile does not exist: $DOCKERFILE_PATH"
        exit 1
    fi

    if [ ! -f "$DOCKER_DIR/docker-compose.yml" ]; then
        print_error "docker-compose.yml does not exist: $DOCKER_DIR/docker-compose.yml"
        exit 1
    fi

    if [ ! -f "$DOCKER_DIR/.env" ]; then
        print_warning ".env file does not exist, default configuration will be used"
    fi

    print_success "File check complete"
}

# Build the Studio image
build_studio() {
    local no_cache=$1

    print_header "Building Supabase Studio image"

    print_info "Image name: $STUDIO_IMAGE"
    print_info "Dockerfile: $DOCKERFILE_PATH"

    # Build arguments
    BUILD_ARGS="--target production -t $STUDIO_IMAGE -f $DOCKERFILE_PATH"

    if [ "$no_cache" = "true" ]; then
        print_warning "Using the --no-cache option, will do a full rebuild"
        BUILD_ARGS="$BUILD_ARGS --no-cache"
    fi

    print_info "Starting build..."
    echo ""

    # Run the build
    if docker build $BUILD_ARGS .; then
        echo ""
        print_success "Image built successfully: $STUDIO_IMAGE"

        # Show image info
        print_info "Image info:"
        docker images $STUDIO_IMAGE --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"
    else
        echo ""
        print_error "Image build failed"
        exit 1
    fi
}

# Start services
start_services() {
    print_header "Starting Supabase services"

    cd "$DOCKER_DIR"

    print_info "Starting all services..."
    if docker compose up -d; then
        echo ""
        print_success "Services started successfully"
        echo ""
        print_info "🌐 Access URLs:"
        echo "   - Supabase Studio: http://localhost:3000"
        echo "   - API Gateway:      http://localhost:8000"
        echo "   - Database:         localhost:5432"
        echo "   - Analytics:        http://localhost:4000"
        echo ""
        print_info "💡 Tips:"
        echo "   - View logs: ./build-and-start.sh --logs"
        echo "   - View status: ./build-and-start.sh --status"
        echo "   - Stop services: ./build-and-start.sh --stop"
    else
        print_error "Failed to start services"
        exit 1
    fi

    cd - > /dev/null
}

# Stop services
stop_services() {
    print_header "Stopping Supabase services"

    cd "$DOCKER_DIR"

    if docker compose down; then
        print_success "Services stopped"
    else
        print_error "Failed to stop services"
        exit 1
    fi

    cd - > /dev/null
}

# Restart services
restart_services() {
    print_header "Restarting Supabase services"

    cd "$DOCKER_DIR"

    if docker compose restart; then
        print_success "Services restarted"
    else
        print_error "Failed to restart services"
        exit 1
    fi

    cd - > /dev/null
}

# View service status
show_status() {
    print_header "Supabase service status"

    cd "$DOCKER_DIR"
    docker compose ps
    cd - > /dev/null
}

# View logs
show_logs() {
    local service=$1

    cd "$DOCKER_DIR"

    if [ -z "$service" ]; then
        print_info "Viewing logs for all services (Ctrl+C to exit)..."
        docker compose logs -f
    else
        print_info "Viewing logs for the $service service (Ctrl+C to exit)..."
        docker compose logs -f "$service"
    fi

    cd - > /dev/null
}

# Clean up services and data
clean_all() {
    print_header "Cleaning up Supabase services"

    print_warning "This will stop all services and delete containers and data volumes"
    read -p "Are you sure you want to continue? (yes/no) " -r
    echo ""

    if [[ $REPLY == "yes" ]]; then
        cd "$DOCKER_DIR"

        print_info "Stopping and cleaning up all containers and data..."
        if docker compose down -v --remove-orphans; then
            print_success "Cleanup complete"
        else
            print_error "Cleanup failed"
            exit 1
        fi

        cd - > /dev/null
    else
        print_info "Cancelled"
    fi
}

# Main function
main() {
    local build_only=false
    local no_cache=false
    local skip_build=false
    local action="build_and_start"
    local log_service=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --build-only)
                build_only=true
                action="build"
                shift
                ;;
            --no-cache)
                no_cache=true
                shift
                ;;
            --skip-build)
                skip_build=true
                action="start"
                shift
                ;;
            --stop)
                action="stop"
                shift
                ;;
            --restart)
                action="restart"
                shift
                ;;
            --status)
                action="status"
                shift
                ;;
            --logs)
                action="logs"
                if [[ $# -gt 1 && ! $2 =~ ^-- ]]; then
                    log_service=$2
                    shift
                fi
                shift
                ;;
            --clean)
                action="clean"
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                echo ""
                show_help
                exit 1
                ;;
        esac
    done

    # Perform the requested action
    case $action in
        build)
            check_docker
            check_files
            build_studio "$no_cache"
            ;;
        start)
            check_docker
            check_files
            start_services
            ;;
        build_and_start)
            check_docker
            check_files
            build_studio "$no_cache"
            echo ""
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
            show_logs "$log_service"
            ;;
        clean)
            clean_all
            ;;
    esac
}

# Run the main function
main "$@"
