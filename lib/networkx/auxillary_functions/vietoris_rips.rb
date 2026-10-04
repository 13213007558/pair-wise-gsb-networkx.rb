module NetworkX
  RIPS_PERSISTENCE_MAX_NODES = 32

  # Builds the dimension-two Vietoris-Rips filtration of a small undirected distance graph
  # and computes persistent H0 and H1 over F2.
  #
  # Vertices are born at zero. An edge is born at its non-negative distance. A triangle
  # is born at the largest distance among its three edges. Equal filtration values use
  # vertices, then edges, then triangles, with ties ordered by the stable insertion
  # order of graph nodes; every face therefore appears before its cofaces.
  #
  # @param graph [Graph] an undirected simple graph with non-negative edge distances
  # @param weight_attr [Symbol] edge attribute containing the distance (default :weight)
  # @param max_nodes [Integer] explicit graph-size limit, at most 32 nodes
  #
  # @return [Hash] filtration simplices and H0/H1 persistence intervals with creator and killer
  def self.vietoris_rips_persistence(graph, weight_attr: :weight, max_nodes: RIPS_PERSISTENCE_MAX_NODES)
    raise ArgumentError, 'Vietoris-Rips persistence requires an undirected simple graph.' if graph.directed? || graph.multigraph?
    raise ArgumentError, 'max_nodes must be an Integer.' unless max_nodes.is_a?(Integer)
    raise ArgumentError, "max_nodes cannot exceed #{RIPS_PERSISTENCE_MAX_NODES}." if max_nodes > RIPS_PERSISTENCE_MAX_NODES
    raise ArgumentError, 'max_nodes must be positive.' if max_nodes <= 0
    raise ArgumentError, "graph has #{graph.number_of_nodes} nodes; the small-scale limit is #{max_nodes}." if graph.number_of_nodes > max_nodes

    nodes = graph.nodes
    node_index = {}
    nodes.each_with_index { |node, index| node_index[node] = index }

    edge_weights = {}
    nodes.each_with_index do |node1, index1|
      graph.adj[node1].each do |node2, attrs|
        index2 = node_index.fetch(node2)
        next if index1 > index2
        raise ArgumentError, "self-loops are not allowed: #{node1.inspect}." if index1 == index2

        weight = attrs.fetch(weight_attr, 1)
        valid_weight = weight.is_a?(Numeric) && weight >= 0
        unless valid_weight
          raise ArgumentError, "edge #{node1.inspect}-#{node2.inspect} must have a non-negative numeric distance."
        end

        edge_weights[[index1, index2]] = weight
      end
    end

    simplices = build_rips_simplices(nodes, node_index, edge_weights)
    intervals_from_filtration(simplices)
  end

  def self.build_rips_simplices(nodes, node_index, edge_weights)
    simplices = nodes.map do |node|
      {dimension: 0, vertices: [node], vertex_indices: [node_index[node]], birth: 0}
    end

    edge_weights.each do |(index1, index2), birth|
      simplices << {
        dimension: 1,
        vertices: [nodes[index1], nodes[index2]],
        vertex_indices: [index1, index2],
        birth: birth
      }
    end

    (0...nodes.length).to_a.combination(3) do |index1, index2, index3|
      edges = [[index1, index2], [index1, index3], [index2, index3]]
      next unless edges.all? { |edge| edge_weights.key?(edge) }

      simplices << {
        dimension: 2,
        vertices: [nodes[index1], nodes[index2], nodes[index3]],
        vertex_indices: [index1, index2, index3],
        birth: edges.map { |edge| edge_weights[edge] }.max
      }
    end

    simplices.sort_by! { |simplex| [simplex[:birth], simplex[:dimension], simplex[:vertex_indices]] }
    simplices.each_with_index { |simplex, index| simplex[:index] = index }
  end
  private_class_method :build_rips_simplices

  def self.intervals_from_filtration(simplices)
    columns = Array.new(simplices.length) { Set.new }
    edge_columns = {}

    simplices.each do |simplex|
      indices = simplex[:vertex_indices]
      if simplex[:dimension] == 1
        columns[simplex[:index]] = Set.new(indices.map { |vertex_index| simplices[vertex_index][:index] })
        edge_columns[indices] = simplex[:index]
      elsif simplex[:dimension] == 2
        faces = [
          [indices[0], indices[1]],
          [indices[0], indices[2]],
          [indices[1], indices[2]]
        ]
        columns[simplex[:index]] = Set.new(faces.map { |face| edge_columns[face] })
      end
    end

    pairs, positive_columns = reduce_boundary_matrix(columns)
    build_persistence_result(simplices, pairs, positive_columns)
  end
  private_class_method :intervals_from_filtration

  def self.reduce_boundary_matrix(columns)
    pivot_columns = {}
    pairs = []
    positive_columns = Set.new

    columns.each_with_index do |column, column_index|
      until column.empty?
        pivot = column.max
        reducing_column = pivot_columns[pivot]
        if reducing_column
          columns[reducing_column].each do |index|
            if column.include?(index)
              column.delete(index)
            else
              column.add(index)
            end
          end
        else
          pairs << [pivot, column_index]
          break
        end
      end
      pivot_columns[column.max] = column_index unless column.empty?
      positive_columns << column_index if column.empty?
    end

    [pairs, positive_columns]
  end
  private_class_method :reduce_boundary_matrix

  def self.build_persistence_result(simplices, pairs, positive_columns)
    pairs_by_dimension = pairs.group_by { |creator, _killer| simplices[creator][:dimension] }
    killed_creators = pairs.map(&:first).to_set

    {
      simplices: simplices.map { |simplex| simplex_output(simplex) },
      h0: persistence_intervals(simplices, pairs_by_dimension[0] || [], killed_creators, positive_columns, 0),
      h1: persistence_intervals(simplices, pairs_by_dimension[1] || [], killed_creators, positive_columns, 1)
    }
  end
  private_class_method :build_persistence_result

  def self.persistence_intervals(simplices, pairs, killed_creators, positive_columns, dimension)
    intervals = pairs.sort_by(&:first).map do |creator, killer|
      [creator, interval(simplices[creator], simplices[killer])]
    end

    simplices.each do |simplex|
      next unless simplex[:dimension] == dimension && positive_columns.include?(simplex[:index]) &&
                  !killed_creators.include?(simplex[:index])

      intervals << [simplex[:index], interval(simplex, nil)]
    end

    intervals.sort_by(&:first).map(&:last)
  end
  private_class_method :persistence_intervals

  def self.interval(creator, killer)
    {
      dimension: creator[:dimension],
      birth: creator[:birth],
      death: killer.nil? ? Float::INFINITY : killer[:birth],
      creator: simplex_identity(creator),
      killer: killer.nil? ? nil : simplex_identity(killer)
    }
  end
  private_class_method :interval

  def self.simplex_output(simplex)
    simplex_identity(simplex).merge(index: simplex[:index], birth: simplex[:birth])
  end
  private_class_method :simplex_output

  def self.simplex_identity(simplex)
    {dimension: simplex[:dimension], vertices: simplex[:vertices].dup}
  end
  private_class_method :simplex_identity
end
