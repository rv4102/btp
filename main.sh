#!/bin/bash

if [ $# -ne 1 ]; then
    echo "Usage: $0 <input.cpp>"
    exit 1
fi

input_file="$1"
output_file="${input_file%.cpp}_modified.cpp"

# get line number of the asm volatile block
asm_volatile_line=$(grep -n "asm volatile" "$input_file" | cut -d: -f1)

# get number of lines between the opening bracket of asm volatile block and closing bracket
num_instructions=$(grep -n "asm volatile" "$input_file" | cut -d: -f1 | while read line; do
    sed -n "${line},/);/p" "$input_file" | wc -l
done)
num_instructions=$((num_instructions-5))

# Copy the original file to a new file
cat "$input_file" > "temp.cpp"

mkdir -p outputs

for ((i=1; i<=num_instructions; i++)); do
    j=$(($asm_volatile_line+$i))
    echo "Line $j is being measured!"

    # at each iteration, uncomment the jth line
    sed -e "${j}s/\/\/ //" "$input_file" > "$output_file"
    cat "$output_file" > "$input_file" 

    # Compile the modified C code
    g++ -o output "$output_file" -L./measure -I./measure -l:libmeasure.a

    # Run the code
    sudo taskset -c 1 ./output > "outputs/${i}_output.txt"

    if [ $i -ne 1 ]; then
        # subtract the previous output from the current output
        paste "outputs/$((i-1))_output.txt" "outputs/${i}_output.txt" | awk '{print $1 - $2}' > "outputs/inst_${i}.txt"
    else
        cat "outputs/${i}_output.txt" > "outputs/inst_${i}.txt"
    fi

    # Clean up
    rm output "$output_file"
done

# Restore the original file
cat "temp.cpp" > "$input_file"
rm "temp.cpp"

echo "Contract trace created"


input_file_ht="${input_file%.cpp}_ht.cpp"

# Copy the original file to a new file
cat "$input_file_ht" > "temp.cpp"

# get line number of the asm volatile block
asm_volatile_line=$(grep -n "asm volatile" "$input_file_ht" | cut -d: -f1)

for ((i=1; i<=num_instructions; i++)); do
    j=$(($asm_volatile_line+$i))
    echo "Line $j is being measured!"

    # at each iteration, uncomment the jth line
    sed -e "${j}s/\/\/ //" "$input_file_ht" > "$output_file"
    cat "$output_file" > "$input_file_ht" 

    # Compile the modified C code
    g++ -o output "$output_file" -L./measure -I./measure -l:libmeasure.a

    # Run the code
    sudo taskset -c 1 ./output > "outputs/${i}_output_ht.txt"

    if [ $i -ne 1 ]; then
        # subtract the previous output from the current output
        paste "outputs/$((i-1))_output_ht.txt" "outputs/${i}_output_ht.txt" | awk '{print $1 - $2}' > "outputs/inst_${i}_ht.txt"
    else
        cat "outputs/${i}_output_ht.txt" > "outputs/inst_${i}_ht.txt"
    fi

    # Clean up
    rm output "$output_file"
done

# Restore the original file
cat "temp.cpp" > "$input_file_ht"
rm "temp.cpp"

echo "Hardware trace created"

# Run TVLA
for ((i=1; i<=num_instructions; i++)); do
    result=$(python3 tvla.py "outputs/inst_${i}.txt" "outputs/inst_${i}_ht.txt")
    if [ $result -eq 1 ]; then
        echo "Violation found at instruction $i"
        exit 0
    fi
done

echo "No violation found"
