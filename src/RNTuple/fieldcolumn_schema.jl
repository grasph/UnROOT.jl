_parse_field(field_id, field_records, column_records, alias_columns, role) = error("Don't know how to handle role = $role")

"""
    StdArrayField<N, T>

Special base-case field for a leaf field representing `std::array<T, N>`. This is because RNTuple
would serialize it as a leaf field but with `flags == 0x0001` in the field description.
In total, there are two field descriptions associlated with `array<>`, one for meta-data (the `N`),
the other one for the actual data.
"""
struct StdArrayField{N, T}
    content_col::T
    StdArrayField(N, col::T) where T = new{N, T}(col)
end

"""
    StringField

Special base-case field for String leaf field. This is because RNTuple
splits a leaf String field into two columns (instead of split in field records).
So we need an offset column and a content column (that contains `Char`s).
"""
struct StringField{O, T}
    offset_col::O
    content_col::T
end

"""
    struct LeafField{T}
        content_col_idx::Int
    end

Base case of field nesting, this links to a column in the RNTuple by 0-based index.
`T` is the `eltype` of this field which mostly uses Julia native types except for
`Switch`.
"""
struct LeafField{T}
    content_col_idx::Int
    nbits::Int
end

function _search_col_type(field_id, column_records, col_id::Int...)
    if length(col_id) == 2 && 
        # String is the only known leaf field that splits in column records
        column_records[col_id[1]].type == 2 && 
        column_records[col_id[2]].type == 5
        return StringField(LeafField{Int32}(col_id[1], 32), LeafField{Char}(col_id[2], 8))
    elseif length(col_id) == 1
        record = column_records[only(col_id)]
        return LeafField{rntuple_col_type_dict[record.type]}(only(col_id), record.nbits)
    else
        error("un-handled base case, report issue to authors")
    end
end

function find_alias(field_id, alias_columns)::Int
    for a in alias_columns
        if a.field_id == field_id
            return a.physical_id
        end
    end
    return -1
end

function _search_col_type(field_id, column_records::Vector, alias_columns::Vector)
    col_id = Tuple(findall(column_records) do col
        col.field_id == field_id
    end)
    physical_id = find_alias(field_id, alias_columns)

    if physical_id != -1
        _search_col_type(field_id, column_records, physical_id + 1)
    elseif !isempty(col_id)
        _search_col_type(field_id, column_records, col_id...)
    else
        error("Unreachable reached, no alias column and empty column match")
    end
end


function _parse_field(field_id, field_records, column_records, alias_columns, ::Val{rntuple_role_leaf})
    # field_id in 0-based index
    field = field_records[field_id + 1]
    if iszero(field.repetition)
        return _search_col_type(field_id, column_records, alias_columns)
    else
        # `std::array<>` for some reason splits in Field records and pretent to be a leaf field
        element_idx = findlast(field_records) do field
            field.parent_field_id == field_id
        end
        sub_field = field_records[element_idx]
        content_col =  _parse_field(element_idx - 1, field_records, column_records, alias_columns, Val(sub_field.struct_role))
        return StdArrayField(field.repetition, content_col)
    end
end

struct VectorField{O, T}
    offset_col::O
    content_col::T
end

function _parse_field(field_id, field_records, column_records, alias_columns, ::Val{rntuple_role_vector})
    offset_col = _search_col_type(field_id, column_records, alias_columns)

    element_idx = findlast(field_records) do field
        field.parent_field_id == field_id
    end
    # go back to 0-based
    content_col = _parse_field(element_idx-1, field_records, 
                               column_records, alias_columns, Val(field_records[element_idx].struct_role))

    return VectorField(offset_col, content_col)
end

# the parent field is only structral, no column attached
struct StructField{N, T}
    content_cols::T
end

function _parse_field(field_id, field_records, column_records, alias_columns, ::Val{rntuple_role_struct})
    element_ids = findall(field_records) do field
        field.parent_field_id == field_id
    end
    # need 1-based index here
    setdiff!(element_ids, field_id+1) # ignore itself
    sub_fields = @view field_records[element_ids]

    names = Tuple(Symbol(sub_field.field_name) for sub_field in sub_fields)
    content_cols = Tuple(
        _parse_field(element_idx-1, field_records, column_records, alias_columns, Val(sub_field.struct_role))
    for (element_idx, sub_field) in zip(element_ids, sub_fields)
    )

    return StructField{names, typeof(content_cols)}(content_cols)
end

struct UnionField{S, T}
    switch_col::S
    content_cols::T
end

function _parse_field(field_id, field_records, column_records, alias_columns, ::Val{rntuple_role_union})
    switch_col = _search_col_type(field_id, column_records, alias_columns)
    element_ids = findall(field_records) do field
        field.parent_field_id == field_id
    end
    # need 1-based index here
    setdiff!(element_ids, field_id+1)
    sub_fields = @view field_records[element_ids]

    content_cols = Tuple(
        _parse_field(element_idx-1, field_records, column_records, alias_columns, Val(sub_field.struct_role))
    for (element_idx, sub_field) in zip(element_ids, sub_fields)
    )

    return UnionField(switch_col, content_cols)
end

function parse_fields(hr::RNTupleHeader)
    parse_fields(hr.field_records, hr.column_records, hr.alias_columns)
end

function parse_fields(field_records, column_records, alias_columns)
    fields = Dict{Symbol, Any}()
    for (idx, field) in enumerate(field_records)
        this_id = idx - 1 # 0-based
        if this_id == field.parent_field_id
            fields[Symbol(field.field_name)] = _parse_field(
                                                            this_id,
                                                            field_records,
                                                            column_records,
                                                            alias_columns,
                                                            Val(field.struct_role)
                                                           )
        end
    end
    NamedTuple(fields)
end
