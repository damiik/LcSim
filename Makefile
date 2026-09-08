CXX ?= g++
AR ?= ar
PYTHON ?= python3
CXXFLAGS ?= -O3 -DNDEBUG -std=c++17 -Wall -Wextra
CPPFLAGS += -Iinclude
RAYLIB_DIR ?= ../third_party/raylib
RAYLIB_CFLAGS ?= -I$(RAYLIB_DIR)/src
RAYLIB_LIBS ?= -L$(RAYLIB_DIR)/src -lraylib -lGL -lm -lpthread -ldl -lrt -lX11
DESIGN ?= examples/counter.toml
BUILD ?= build
CORE = $(BUILD)/simulator.o $(BUILD)/scope.o
.PHONY: all headless gui tools test clean FORCE
all: headless
$(BUILD):
	mkdir -p $@
$(BUILD)/%.o: src/%.cpp $(wildcard include/lcsim/*.hpp) | $(BUILD)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -c $< -o $@
$(BUILD)/liblcsim.a: $(CORE)
	$(AR) rcs $@ $^
FORCE:
$(BUILD)/design.cpp: $(DESIGN) tools/lc_compile.py FORCE | $(BUILD)
	$(PYTHON) tools/lc_compile.py "$(DESIGN)" "$@"
headless: $(BUILD)/lcsim
$(BUILD)/lcsim: $(BUILD)/design.cpp src/main.cpp $(BUILD)/liblcsim.a
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) $^ -o $@
$(BUILD)/liblcsim_symbols.a: src/gui.cpp $(wildcard include/lcsim/*.hpp) | $(BUILD)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(RAYLIB_CFLAGS) -c src/gui.cpp -o $(BUILD)/gui.o
	$(AR) rcs $@ $(BUILD)/gui.o
gui: $(BUILD)/lcsim-gui
tools: headless gui
$(BUILD)/lcsim-gui: $(BUILD)/design.cpp src/main.cpp $(BUILD)/liblcsim_symbols.a $(BUILD)/liblcsim.a
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(RAYLIB_CFLAGS) -DLCSIM_GUI $^ $(RAYLIB_LIBS) -o $@
test: $(BUILD)/liblcsim.a
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) tests/runtime.cpp $(BUILD)/liblcsim.a -o $(BUILD)/tests
	$(BUILD)/tests
	$(PYTHON) -m unittest discover -s tests -p 'test_*.py'
clean:
	rm -rf $(BUILD)

.PHONY: test-cpu
$(BUILD)/cpu.cpp: examples/cpu65c02.toml tools/lc_compile.py | $(BUILD)
	$(PYTHON) tools/lc_compile.py "$<" "$@"
test-cpu: $(BUILD)/cpu.cpp $(BUILD)/liblcsim.a
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) tests/cpu.cpp $^ -o $(BUILD)/test-cpu
	$(BUILD)/test-cpu

.PHONY: test-extended
test: test-extended
test-extended: $(BUILD)/liblcsim.a
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) tests/extended.cpp $^ -o $(BUILD)/test-extended
	$(BUILD)/test-extended
