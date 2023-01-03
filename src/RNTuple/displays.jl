# stop crazy stracktrace
function Base.show(io::IO, ::Type{<:RNTuple{O, NamedTuple{N, T}}}) where {O, N, T}
    print(io, "RNTuple{$N}")
end

function Base.show(io::IO, f::ClusterSummary)
    print(io, "ClusterSummary(num_first_entry=$(f.num_first_entry), ")
    print(io, "num_entries=$(f.num_entries))")
end

function Base.show(io::IO, f::FieldRecord)
    print(io, "parent=$(lpad(Int(f.parent_field_id), 2, "0")), ")
    print(io, "role=$(Int(f.struct_role)), ")
    print(io, "name=$(rpad(f.field_name, 30, " ")), ")
    print(io, "type=$(rpad(f.type_name, 60, " "))")
    # print(io, "alias=$(f.type_alias),")
    # print(io, "desc=$(f.field_desc),")
end

function Base.show(io::IO, f::ColumnRecord)
    print(io, "type=$(lpad(Int(f.type), 2, "0")), ")
    print(io, "nbits=$(lpad(Int(f.nbits), 2, "0")), ")
    print(io, "field_id=$(lpad(Int(f.field_id), 2, "0")), ")
    print(io, "flags=$(f.flags)")
end

function Base.show(io::IO, lf::StringField)
    print(io, "String(offset=$(lf.offset_col.content_col_idx), char=$(lf.content_col.content_col_idx))")
end
function Base.show(io::IO, lf::LeafField{T}) where T
    print(io, "Leaf{$T}(col=$(lf.content_col_idx))")
end
function Base.show(io::IO, lf::VectorField)
    print(io, "VectorField(offset=$(lf.offset_col), content=$(lf.content_col))")
end
function Base.show(io::IO, lf::StructField{N, T}) where {N, T}
    print(io, replace("StructField{$(N .=> lf.content_cols))", " => " => "="))
end

function Base.show(io::IO, lf::UnionField)
    print(io, "UnionField(switch=$(lf.switch_col), content=$(lf.content_cols))")
end
function Base.summary(io::IO, uv::UnionVector{T, N}) where {T, N}
    print(io, "$(length(uv))-element UnionVector{$T}")
end

function Base.summary(io::IO, rf::RNTupleField{R, F, O, E}) where {R, F, O, E}
    print(io, "$(length(rf))-element RNTupleField{$E}")
end
