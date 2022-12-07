# using Wasmer
# 
# weakRef = WeakKeyDict()
# 
# function loadWasm(path)
	# engine = get!(task_local_storage(), :wasmengine) do
		# WasmEngine()
	# end
	# 
	# store = get!(task_local_storage(), :wasmstore) do
		# WasmStore(task_local_storage(:wasmengine))
	# end
	# 
	# code = read(path)
	# codevec = Wasmer.WasmVec(code)
	# modu = WasmModule(store, codevec)
	# instance = WasmInstance(store, modu)
	# wasmexports =  exports(instance)
	# for exported in wasmexports.wasm_exports
		# if startswith(exported.name, "julia_")
			# funcName = Symbol(join(split(exported.name, "_")[2:end]))
			# eval(:($funcName = $exported))
			# weakRef[:funcName] = exported
		# end
	# end
# end

# # Usage
# loadWasm("temp/constMul.wasm")
# constMul(Int32(1))

# TODO check if its wasm32 or wasm64 
# Also adapt the values passed to the functions using Adapt.jl

# Wasi dependendency cases  ?
