#!/bin/bash

# Validation script for Press Connect watermark implementation
# This script checks that all necessary files and configurations are in place

echo "🔍 Press Connect Watermark Implementation Validation"
echo "================================================"

# Check Flutter project structure
echo "📁 Checking project structure..."

if [ -f "press_connect/pubspec.yaml" ]; then
    echo "✅ Flutter project found"
else
    echo "❌ Flutter project not found"
    exit 1
fi

# Check required dependencies
echo "📦 Checking dependencies..."

dependencies=("rtmp_broadcaster" "ffmpeg_kit_flutter_new" "camera" "provider")
for dep in "${dependencies[@]}"; do
    if grep -q "$dep:" press_connect/pubspec.yaml; then
        echo "✅ $dep dependency found"
    else
        echo "❌ $dep dependency missing"
    fi
done

# Check watermark assets
echo "🖼️ Checking watermark assets..."

if [ -f "press_connect/assets/watermarks/default_watermark.png" ]; then
    echo "✅ Default watermark image found"
    
    # Check file size (should be reasonable)
    size=$(wc -c < "press_connect/assets/watermarks/default_watermark.png")
    if [ $size -gt 1000 ] && [ $size -lt 5000000 ]; then
        echo "✅ Watermark image size is reasonable ($size bytes)"
    else
        echo "⚠️ Watermark image size may be too large or too small ($size bytes)"
    fi
else
    echo "❌ Default watermark image not found"
fi

# Check configuration files
echo "⚙️ Checking configuration..."

if [ -f "press_connect/assets/config.json" ]; then
    echo "✅ Configuration file found"
    
    # Check for watermark config
    if grep -q "watermark" press_connect/assets/config.json; then
        echo "✅ Watermark configuration found"
    else
        echo "❌ Watermark configuration missing"
    fi
else
    echo "❌ Configuration file not found"
fi

# Check implementation files
echo "🔧 Checking implementation files..."

files=(
    "press_connect/lib/services/live_service.dart"
    "press_connect/lib/services/watermark_service.dart"
    "press_connect/lib/ui/screens/go_live_screen.dart"
)

for file in "${files[@]}"; do
    if [ -f "$file" ]; then
        echo "✅ $file found"
        
        # Check for TODO comments (excluding node_modules)
        if grep -q "TODO\|todo" "$file" 2>/dev/null; then
            echo "⚠️ TODO comments still present in $file"
        fi
    else
        echo "❌ $file not found"
    fi
done

# Check backend implementation
echo "🖥️ Checking backend implementation..."

if [ -f "backend/src/live.controller.js" ]; then
    echo "✅ Live controller found"
    
    # Check for required endpoints
    endpoints=("createLiveStream" "startLiveStream" "endLiveStream")
    for endpoint in "${endpoints[@]}"; do
        if grep -q "$endpoint" backend/src/live.controller.js; then
            echo "✅ $endpoint endpoint found"
        else
            echo "❌ $endpoint endpoint missing"
        fi
    done
else
    echo "❌ Live controller not found"
fi

# Check documentation
echo "📚 Checking documentation..."

if [ -f "WATERMARK_IMPLEMENTATION.md" ]; then
    echo "✅ Watermark implementation documentation found"
else
    echo "❌ Watermark implementation documentation missing"
fi

if [ -f "CONFIGURATION.md" ]; then
    echo "✅ Configuration documentation found"
else
    echo "⚠️ Configuration documentation not found"
fi

echo ""
echo "🎯 Validation Summary"
echo "===================="

# Count checks
total_files=$(find . -name "*.dart" -o -name "*.js" | grep -v node_modules | wc -l)
todo_count=$(grep -r "TODO\|todo" --include="*.dart" --include="*.js" . --exclude-dir=node_modules 2>/dev/null | wc -l)

echo "📊 Total source files: $total_files"
echo "📋 Remaining TODOs: $todo_count"

if [ $todo_count -eq 0 ]; then
    echo "✅ All TODOs have been resolved!"
else
    echo "⚠️ Some TODOs remain - check implementation"
fi

echo ""
echo "🚀 Next Steps:"
echo "1. Run 'flutter pub get' in press_connect directory"
echo "2. Run 'npm install' in backend directory"
echo "3. Configure your actual backend URL in config.json"
echo "4. Set up YouTube API credentials"
echo "5. Test the application with a real device"
echo ""
echo "For detailed setup instructions, see CONFIGURATION.md"