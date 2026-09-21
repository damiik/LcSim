# 1. Generate design.nim
mkdir -p build-nim
python3 scripts/lc_compile_nim.py examples/cpu65c02-wozmon_v5.toml build-nim/design.nim

# 2. Compile Nim (release + speed)
nim c -d:release --opt:speed --passC:-march=native --passC:-flto \
    --path:build-nim --path:nim \
    -o:build-nim/lcsim-nim nim/main.nim

# 3. Run
./build-nim/lcsim-nim --steps 500000 --technology lvc