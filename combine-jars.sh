#!/bin/bash
# Script to combine two Java JAR files, specifically designed to merge
# resources, classes, and multi-platform native libraries without conflicts.

# --- Configuration ---
JAR1=""
JAR2=""
OUTPUT_JAR=""
TEMP_DIR="temp_combined_jar_staging_$(date +%s)"
DOWNLOADED_JAR1="" # Track downloaded JAR path 1 for cleanup
DOWNLOADED_JAR2="" # Track downloaded JAR path 2 for cleanup

# --- Functions ---

# Function to display usage information
show_usage() {
    echo "Usage: $0 --input-jar <path/to/jar1/or/url> --input-jar <path/to/jar2/or/url> --output-jar <output_name>"
    echo "Example 1 (Local files): $0 --input-jar a.jar --input-jar b.jar --output-jar combined.jar"
    echo "Example 2 (Remote file): $0 --input-jar a.jar --input-jar https://example.com/b.jar --output-jar combined.jar"
    echo ""
    echo "This script safely combines the contents of two JARs, overwriting duplicate"
    echo "files (like class files or manifests) but preserving non-conflicting content,"
    echo "such as native libraries located in different architecture subdirectories."
}

# Function to perform cleanup
cleanup() {
    if [ -d "$TEMP_DIR" ]; then
        echo "Cleaning up temporary directory: $TEMP_DIR"
        rm -rf "$TEMP_DIR"
    fi
    # Cleanup downloaded files
#    if [ -n "$DOWNLOADED_JAR1" ] && [ -f "$DOWNLOADED_JAR1" ]; then
#        echo "Cleaning up downloaded file: $DOWNLOADED_JAR1"
#        rm -f "$DOWNLOADED_JAR1"
#    fi
#    if [ -n "$DOWNLOADED_JAR2" ] && [ -f "$DOWNLOADED_JAR2" ]; then
#        echo "Cleaning up downloaded file: $DOWNLOADED_JAR2"
#        rm -f "$DOWNLOADED_JAR2"
#    fi
}

# Function to download a file if the input is a URL
# Arguments: $1 = input path/URL, $2 = variable name to store downloaded path for cleanup tracking
download_if_needed() {
    local input_path="$1"
    local var_name="$2"
    local downloaded_path=""
    local file_name=""

    if [[ "$input_path" =~ ^https?:// ]]; then
        # It's a URL, attempt to download
        file_name=$(basename "$input_path")
        if [ -z "$file_name" ] || [ "$file_name" == "/" ]; then
            file_name="downloaded_jar_$(date +%s)_$RANDOM.jar"
        fi
        # Downloaded file is temporarily placed in the current directory
        downloaded_path="./$file_name"

        echo "Downloading $input_path to $downloaded_path..." >&2
        # -f: Fail silently (no HTML output) on server errors
        # -s: Silent mode (suppress progress meter)
        # -S: Show error message if silent fails
        # -L: Follow redirects
        # -o: Output to file
        if ! curl -fsSL -o "$downloaded_path" "$input_path"; then
            echo "Error: Failed to download JAR from $input_path" >&2
            return 1
        fi

        # Set the tracking variable (e.g., DOWNLOADED_JAR1)
        # We use eval to set the variable passed by name in the parent scope
        eval "${var_name}='${downloaded_path}'"

        # Return the local path
        echo "$downloaded_path"
    else
        # Not a URL, return the original path
        echo "$input_path"
    fi
    return 0
}

# --- Main Script Execution ---

# 1. Argument Parsing and Setting
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --input-jar)
            if [ -z "$2" ]; then
                echo "Error: Missing value for $1" >&2
                exit 1
            fi
            if [ -z "$JAR1" ]; then
                JAR1="$2"
            elif [ -z "$JAR2" ]; then
                JAR2="$2"
            else
                echo "Error: Only two --input-jar arguments are allowed." >&2
                show_usage
                exit 1
            fi
            shift 2
            ;;
        --output-jar)
            if [ -z "$2" ]; then
                echo "Error: Missing value for $1" >&2
                exit 1
            fi
            OUTPUT_JAR="$2"
            shift 2
            ;;
        *)
            echo "Error: Unknown argument '$1'" >&2
            show_usage
            exit 1
            ;;
    esac
done

# 2. Initial Validation
if [ -z "$JAR1" ] || [ -z "$JAR2" ] || [ -z "$OUTPUT_JAR" ]; then
    echo "Error: Missing required arguments. Both input JARs and the output JAR must be specified." >&2
    show_usage
    exit 1
fi

# Check for curl dependency if URLs are likely to be used
if [[ "$JAR1" =~ ^https?:// ]] || [[ "$JAR2" =~ ^https?:// ]]; then
    if ! command -v curl &> /dev/null; then
        echo "Error: 'curl' command is required for downloading URLs but was not found. Please install curl or use local file paths." >&2
        exit 1
    fi
fi

# Ensure cleanup runs on exit or error
trap cleanup EXIT

echo "--- JAR Merger Started ---"
echo "Input 1: $JAR1"
echo "Input 2: $JAR2"
echo "Output:  $OUTPUT_JAR"

# 3. Pre-process JAR1 and JAR2 (Download if needed)
# NEW_JAR1 and NEW_JAR2 will hold the local path (either original or downloaded)
JAR1_PATH=$(download_if_needed "$JAR1" "DOWNLOADED_JAR1")
if [ $? -ne 0 ]; then exit 1; fi

JAR2_PATH=$(download_if_needed "$JAR2" "DOWNLOADED_JAR2")
if [ $? -ne 0 ]; then exit 1; fi

# 4. Final Input File Validation (using the potentially new local paths)
if [ ! -f "$JAR1_PATH" ] || [ ! -f "$JAR2_PATH" ]; then
    echo "Error: One or both input JAR files not found or downloaded file missing."
    show_usage
    exit 1
fi

# 5. Create Staging Directory
echo "Creating staging directory: $TEMP_DIR"
mkdir -p "$TEMP_DIR"

# 6. Extract Contents
echo "Extracting contents of $JAR1_PATH..."
# The '-o' flag automatically overwrites files without prompting
if ! unzip -o "$JAR1_PATH" -d "$TEMP_DIR" > /dev/null; then
    echo "Error: Failed to extract $JAR1_PATH."
    exit 1
fi

echo "Extracting contents of $JAR2_PATH..."
# Extracting the second JAR. Unique native library folders will be merged.
if ! unzip -o "$JAR2_PATH" -d "$TEMP_DIR" > /dev/null; then
    echo "Error: Failed to extract $JAR2_PATH."
    exit 1
fi

# 7. Create Combined JAR
echo "Creating final combined JAR: $OUTPUT_JAR"
(
    cd "$TEMP_DIR" || exit 1
    # 'jar cf' creates the JAR file from all files in the current directory ('.')
    if jar cf "../$OUTPUT_JAR" .; then
        echo "Successfully created ../$OUTPUT_JAR."
    else
        echo "Error: Failed to create JAR file."
        exit 1
    fi
)

echo "--- JAR Merger Finished Successfully ---"

# The cleanup function will run automatically due to 'trap cleanup EXIT'
exit 0
