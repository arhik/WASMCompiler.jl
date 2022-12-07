function declFix(fn, newFn, mod)
	ctx = LLVM.context(mod)
	for use in LLVM.uses(fn)
		inst = LLVM.user(use)
		if inst isa LLVM.CallInst
			oprnd = LLVM.operands(inst) |> first
			@dispose builder = Builder(ctx) begin
				LLVM.position!(builder, inst)
				newInst = call!(builder, newFn, arguments(inst))
				@warn "NewInst" inst=newInst
				for use in LLVM.uses(inst)
					useInst = LLVM.user(use)
					LLVM.API.LLVMSetOperand(useInst, 0, newInst)
				end
				for use in LLVM.uses(inst)
					useInst = LLVM.user(use)
					if useInst isa LLVM.CallBase
						ff = called_value(useInst)
						@info "Uses" useInst=ff
						fixPointers(ff, mod)
					end
				end
				delete!(LLVM.parent(inst), inst)
			end
			@warn mod
		end
	end
end

function bbFix(bb, mod)
	ctx = LLVM.context(mod)
	for inst in instructions(bb)
		if inst isa LLVM.IntToPtrInst
			oprnd = LLVM.operands(inst) |> first
			if oprnd isa LLVM.TruncInst
				val = LLVM.operands(oprnd) |> first
				if llvmtype(val) == LLVM.Int32Type(ctx)
					LLVM.API.LLVMSetOperand(inst, 0, val)
					delete!(bb, oprnd)
					@warn bb
				else
					@info "Leaving truncation alone"
				end
			end
		end
	end
	for inst in instructions(bb)
		if inst isa LLVM.TruncInst
			for use in LLVM.uses(inst)
				val = LLVM.operands(inst) |> first
				if llvmtype(val) == LLVM.Int32Type(ctx)
					LLVM.API.LLVMSetOperand(LLVM.user(use), 0, val) # TODO get index somehow
					delete!(bb, inst)
					@warn bb
				else
					@info "Leaving truncation alone"
				end
			end
		end
	end
end

function fixPointers(fn::LLVM.Function, mod::LLVM.Module)
	ctx = LLVM.context(mod)
	params = LLVM.parameters(fn)
	
	trackedArgs = []
	
	for (idx, param) in enumerate(params)
		if llvmtype(param) == LLVM.Int64Type(ctx)
			push!(trackedArgs, (idx, llvmtype(param)))
			@error "$param::$(llvmtype(param)) in Function : $(fn) needs to replaced with i32"
		end
	end

	retType = LLVM.return_type(eltype(llvmtype(fn)))
	
	if any((param) -> llvmtype(param) == LLVM.Int64Type(ctx), params) || retType == LLVM.Int64Type(ctx)
		
		newTypes = LLVM.LLVMType[
			llvmtype(param) == LLVM.Int64Type(ctx) ? LLVM.IntType(32; ctx) : llvmtype(param)
			for param in params
		]
		
		retType = let ret = LLVM.return_type(eltype(llvmtype(fn)))
			if ret == LLVM.Int64Type(ctx)
				LLVM.IntType(32; ctx)
			else
				ret
			end
		end
		
		newFType = LLVM.FunctionType(retType, newTypes)
		newFn = LLVM.Function(mod, "clone$(LLVM.name(fn))", newFType)
		linkage!(newFn, linkage(fn))

		@info "replacing i64 return type to i32 in `$fn`"
		declFix(fn, newFn, mod)
		
	    for (arg, new_arg) in zip(parameters(fn), parameters(newFn))
       		LLVM.name!(new_arg, LLVM.name(arg))
   		end
		
		newArgs = parameters(newFn) # LLVM.Argument[]

		valueMap = Dict{LLVM.Value, LLVM.Value}(
			param => newArgs[i] for (i, param) in enumerate(parameters(fn))
		)
		
		valueMap[fn] = newFn;

		@warn mod
		
		clone_into!(
			newFn,
			fn;
			value_map = valueMap,
			changes=LLVM.API.LLVMCloneFunctionChangeTypeGlobalChanges
		)
		
		fname = LLVM.name(fn)
		@info LLVM.FunctionAttrSet(fn, LLVM.API.LLVMAttributeIndex(0))
		!LLVM.isdeclaration(fn) && @assert isempty(uses(fn))
		replace_metadata_uses!(fn, newFn)
		unsafe_delete!(mod, fn)
		LLVM.name!(newFn, fname)
	end
end

function fixBB(fn::LLVM.Function, mod::LLVM.Module)
	ctx = LLVM.context(mod)
	params = LLVM.parameters(fn)
	
	trackedArgs = []
	
	for (idx, param) in enumerate(params)
		if llvmtype(param) == LLVM.Int64Type(ctx)
			push!(trackedArgs, (idx, llvmtype(param)))
			@error "$param::$(llvmtype(param)) in Function : $(fn) needs to replaced with i32"
		end
	end

	retType = LLVM.return_type(eltype(llvmtype(fn)))
	
	# if any((param) -> llvmtype(param) == LLVM.Int64Type(ctx), params) || retType == LLVM.Int64Type(ctx)
		
		newTypes = LLVM.LLVMType[
			llvmtype(param) == LLVM.Int64Type(ctx) ? LLVM.IntType(32; ctx) : llvmtype(param)
			for param in params
		]
		
		retType = let ret = LLVM.return_type(eltype(llvmtype(fn)))
			if ret == LLVM.Int64Type(ctx)
				LLVM.IntType(32; ctx)
			else
				ret
			end
		end
		
		newFType = LLVM.FunctionType(retType, newTypes)
		newFn = LLVM.Function(mod, "clone$(LLVM.name(fn))", newFType)

		linkage!(newFn, linkage(fn))
		
		if LLVM.isdeclaration(fn)
			@info "Declarations should have been fixed by this point"
			# declFix(fn, newFn, mod)
		else
			for bb in blocks(fn)
				@info bb
				bbFix(bb, mod)
			end
		end
		
	    for (arg, new_arg) in zip(parameters(fn), parameters(newFn))
       		LLVM.name!(new_arg, LLVM.name(arg))
   		end
		
		newArgs = parameters(newFn) # LLVM.Argument[]

		valueMap = Dict{LLVM.Value, LLVM.Value}(
			param => newArgs[i] for (i, param) in enumerate(parameters(fn))
		)
		
		valueMap[fn] = newFn;

		@warn mod
		
		clone_into!(
			newFn,
			fn;
			value_map = valueMap,
			changes=LLVM.API.LLVMCloneFunctionChangeTypeGlobalChanges
		)
		
		fname = LLVM.name(fn)
		!LLVM.isdeclaration(fn) && @assert isempty(uses(fn))
		replace_metadata_uses!(fn, newFn)
		unsafe_delete!(mod, fn)
		LLVM.name!(newFn, fname)
	# end
end
