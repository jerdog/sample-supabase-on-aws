import os
from flask import Flask, request, jsonify

app = Flask(__name__)

# Service configuration
SERVICE_NAME = "Functions Service"
SERVICE_VERSION = "1.0.0"

@app.route('/health')
def health():
    """Health check endpoint"""
    return jsonify({
        "status": "healthy",
        "service": SERVICE_NAME,
        "version": SERVICE_VERSION
    }), 200

@app.route('/functions', methods=['GET', 'POST'])
def functions():
    """
    Functions endpoint
    Extracts the project ID from the X-Project-ID header and returns it
    """
    # Get X-Project-ID from the request headers
    project_id = request.headers.get('X-Project-ID')

    # If no project ID was provided
    if not project_id:
        return jsonify({
            "error": "Missing X-Project-ID header",
            "message": "Please provide X-Project-ID in request headers",
            "example": {
                "header": "X-Project-ID",
                "value": "project-alpha"
            }
        }), 400

    # Get the request method
    method = request.method

    # Get query parameters (if any)
    query_params = dict(request.args)

    # Get the request body (if any)
    request_data = None
    if method == 'POST':
        try:
            request_data = request.get_json()
        except:
            request_data = None

    # Build the response
    response = {
        "service": SERVICE_NAME,
        "message": "Functions endpoint accessed successfully",
        "project_id": project_id,
        "method": method,
        "path": request.path,
        "timestamp": str(__import__('datetime').datetime.utcnow()),
    }

    # If there are query parameters, add them to the response
    if query_params:
        response["query_params"] = query_params

    # If there is a request body, add it to the response
    if request_data:
        response["request_data"] = request_data

    return jsonify(response), 200

@app.route('/functions/<path:subpath>', methods=['GET', 'POST', 'PUT', 'PATCH', 'DELETE'])
def functions_subpath(subpath):
    """
    Functions subpath endpoint
    Supports all HTTP methods, returns the project ID and path information
    """
    # Get X-Project-ID from the request headers
    project_id = request.headers.get('X-Project-ID')

    # If no project ID was provided
    if not project_id:
        return jsonify({
            "error": "Missing X-Project-ID header",
            "message": "Please provide X-Project-ID in request headers"
        }), 400

    # Get the request method
    method = request.method

    # Get query parameters (if any)
    query_params = dict(request.args)

    # Get the request body (if any)
    request_data = None
    if method in ['POST', 'PUT', 'PATCH']:
        try:
            request_data = request.get_json()
        except:
            request_data = None

    # Build the response
    response = {
        "service": SERVICE_NAME,
        "message": f"Functions subpath accessed: /{subpath}",
        "project_id": project_id,
        "method": method,
        "path": f"/functions/{subpath}",
        "subpath": subpath,
        "timestamp": str(__import__('datetime').datetime.utcnow()),
    }

    # If there are query parameters, add them to the response
    if query_params:
        response["query_params"] = query_params

    # If there is a request body, add it to the response
    if request_data:
        response["request_data"] = request_data

    return jsonify(response), 200

@app.route('/')
def index():
    """API documentation"""
    return jsonify({
        "service": SERVICE_NAME,
        "version": SERVICE_VERSION,
        "description": "Edge Functions service that extracts and returns project ID from headers",
        "endpoints": {
            "health": {
                "method": "GET",
                "path": "/health",
                "description": "Health check endpoint"
            },
            "functions": {
                "method": "GET, POST",
                "path": "/functions",
                "description": "Main functions endpoint, returns project ID from X-Project-ID header",
                "required_headers": {
                    "X-Project-ID": "Your project identifier (e.g., project-alpha)"
                },
                "example": {
                    "curl": "curl -H 'X-Project-ID: project-alpha' https://api.example.com/functions"
                }
            },
            "functions_subpath": {
                "method": "GET, POST, PUT, PATCH, DELETE",
                "path": "/functions/<subpath>",
                "description": "Functions subpath endpoint, supports all HTTP methods",
                "required_headers": {
                    "X-Project-ID": "Your project identifier"
                },
                "example": {
                    "curl": "curl -H 'X-Project-ID: project-alpha' https://api.example.com/functions/my-function"
                }
            }
        },
        "usage": {
            "project_id_extraction": "Service extracts project ID from X-Project-ID header",
            "response_format": "Returns JSON with project ID and request details",
            "supported_methods": ["GET", "POST", "PUT", "PATCH", "DELETE"]
        }
    }), 200

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 8080))
    app.run(host='0.0.0.0', port=port, debug=False)
