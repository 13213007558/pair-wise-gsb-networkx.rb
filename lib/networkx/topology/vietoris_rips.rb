module NetworkX
  # Small-scale topological data analysis: Vietoris-Rips persistence.
  #
  # Given an undirected graph whose edges carry non-negative distances, the
  # Vietoris-Rips filtration truncated to dimension 2 is built as follows:
  #
  # * every vertex enters the filtration at value 0,
  # * every edge enters at its distance (the +weight+ attribute),
  # * every triangle (3-clique) enters at the maximum of its edge distances.
  #
  # Persistent homology is then computed over the field F2, and the H0 / H1
  # persistence intervals are reported together with the exact simplices that
  # create (birth) and destroy (death) them.
  #
  # Simplices are processed in a reproducible, face-first order: ascending
  # filtration value, then ascending dimension (so a simplex never precedes
  # one of its faces when values tie), then ascending vertex indices (vertices
  # are numbered by insertion order of the graph's nodes).
  #
  # == Worked examples (all edges have distance 1)
  #
  # Triangle on three points a, b, c:
  # * t = 0: vertices a, b, c are born as three H0 classes.
  # * t = 1: edges ab and ac merge components, killing the classes of b and c
  #   (H0 intervals [0, 1]); edge bc closes a cycle, so an H1 class is born.
  # * t = 1: the triangle abc (value max(1, 1, 1) = 1) fills that cycle
  #   immediately, giving the zero-length H1 interval [1, 1].
  # Result: H0 = [0, 1], [0, 1], [0, inf); H1 = [1, 1].
  #
  # Four-cycle a-b-c-d-a:
  # * t = 1: three edges connect the component (H0 [0, 1] x 3), and the last
  #   edge in the deterministic order closes the loop. No triangle ever fills
  #   it, so the H1 class lives forever: [1, inf).
  # Result: H0 = [0, 1] x 3, [0, inf); H1 = [1, inf).
  #
  # Four-cycle plus one diagonal a-c:
  # * the diagonal splits the 4-cycle into two 3-cycles, and the two
  #   triangles abc and acd fill them as soon as they are born.
  # Result: H0 = [0, 1] x 3, [0, inf); H1 = [1, 1], [1, 1].
  #
  # == Size limits
  #
  # Enumerating a clique complex grows quickly (a complete graph on n vertices
  # has n + C(n,2) + C(n,3) simplices up to dimension 2), so the computation
  # refuses to run silently on large inputs: it raises ArgumentError when the
  # graph has more than +max_vertices+ nodes or the filtration would contain
  # more than +max_simplices+ simplices. Pass larger limits explicitly if you
  # really mean it.
  module Topology
    # Default caps guarding against accidental enumeration of huge clique
    # complexes.
    DEFAULT_MAX_VERTICES = 100
    DEFAULT_MAX_SIMPLICES = 10_000

    # One persistence interval.
    #
    # @!attribute dimension [Integer] 0 for components (H0), 1 for loops (H1)
    # @!attribute birth [Numeric] filtration value at which the class appears
    # @!attribute death [Numeric] filtration value at which the class dies,
    #                             Float::INFINITY for essential classes
    # @!attribute birth_simplex [Array<Object>] node labels of the simplex
    #                                           that created the class
    # @!attribute death_simplex [Array<Object>, nil] node labels of the
    #                                               simplex that killed the
    #                                               class, nil when essential
    PersistenceInterval = Struct.new(:dimension, :birth, :death, :birth_simplex, :death_simplex, keyword_init: true) do
      # @return [bool] true if the class never dies
      def essential?
        death == Float::INFINITY
      end

      # @return [Numeric] death - birth (Float::INFINITY for essential classes)
      def persistence
        death - birth
      end
    end

    # Internal simplex record: +vertices+ are node indices in ascending order.
    Simplex = Struct.new(:vertices, :dimension, :value)

    class << self
      # Computes H0 and H1 persistent homology over F2 of the Vietoris-Rips
      # filtration (truncated to dimension 2) of an undirected graph.
      #
      # @example Persistence of a triangle with unit distances
      #   graph = NetworkX::Graph.new
      #   graph.add_edge(1, 2, weight: 1)
      #   graph.add_edge(2, 3, weight: 1)
      #   graph.add_edge(1, 3, weight: 1)
      #   NetworkX::Topology.vietoris_rips_persistence(graph)
      #
      # @param graph [Graph] an undirected graph with non-negative distances
      # @param weight [Object] edge attribute holding the distance
      #                        (missing attributes default to 1)
      # @param max_vertices [Integer] refuse graphs larger than this
      # @param max_simplices [Integer] refuse filtrations larger than this
      #
      # @return [Array<PersistenceInterval>] intervals sorted by dimension,
      #                                      then birth, then death
      def vietoris_rips_persistence(graph, weight: :weight, max_vertices: DEFAULT_MAX_VERTICES,
                                    max_simplices: DEFAULT_MAX_SIMPLICES)
        nodes = graph.nodes
        if nodes.size > max_vertices
          raise ArgumentError, "graph has #{nodes.size} vertices, exceeding the limit of #{max_vertices}; " +                               'pass a larger max_vertices: to override'
        end

        index = {}
        nodes.each_with_index { |node, i| index[node] = i }

        edge_weights = collect_edge_weights(graph, index, weight)
        simplices = build_filtration(nodes.size, edge_weights)
        if simplices.size > max_simplices
          raise ArgumentError, "filtration has #{simplices.size} simplices, exceeding the limit of " +                               "#{max_simplices}; pass a larger max_simplices: to override"
        end

        compute_intervals(simplices, nodes)
      end

      private

      # @return [Hash{Array<Integer> => Numeric}] maps [i, j] (i < j) to distance
      def collect_edge_weights(graph, index, weight)
        edge_weights = {}
        graph.adj.each do |u, u_edges|
          u_edges.each do |v, attrs|
            iu, iv = index[u], index[v]
            next if iu >= iv

            w = attrs.fetch(weight, 1)
            unless w.is_a?(Numeric) && w >= 0
              raise ArgumentError, "edge (#{u.inspect}, #{v.inspect}) has invalid distance #{w.inspect}; " +                                   'distances must be non-negative numbers'
            end
            edge_weights[[iu, iv]] = w
          end
        end
        edge_weights
      end

      # Builds vertices, edges and triangles, sorted in the reproducible
      # face-first filtration order.
      #
      # @return [Array<Simplex>]
      def build_filtration(num_vertices, edge_weights)
        simplices = Array.new(num_vertices) { |i| Simplex.new([i], 0, 0) }
        edge_weights.each { |(i, j), w| simplices << Simplex.new([i, j], 1, w) }
        each_triangle(num_vertices, edge_weights) do |i, j, k, value|
          simplices << Simplex.new([i, j, k], 2, value)
        end
        simplices.sort_by { |s| [s.value, s.dimension, s.vertices] }
      end

      # Yields [i, j, k, value] for every 3-clique; the triangle's filtration
      # value is the maximum of its edge distances.
      def each_triangle(num_vertices, edge_weights)
        (0...num_vertices).each do |i|
          (i + 1...num_vertices).each do |j|
            wij = edge_weights[[i, j]]
            next unless wij

            (j + 1...num_vertices).each do |k|
              wik = edge_weights[[i, k]]
              wjk = edge_weights[[j, k]]
              next unless wik && wjk

              yield i, j, k, [wij, wik, wjk].max
            end
          end
        end
      end

      # Standard F2 boundary-matrix reduction over the sorted simplices.
      #
      # @return [Array<PersistenceInterval>]
      def compute_intervals(simplices, nodes)
        position = {}
        simplices.each_with_index { |s, i| position[s.vertices] = i }

        columns = {}
        low = {}
        creator = Array.new(simplices.size, false)
        killed = Array.new(simplices.size, false)

        simplices.each_with_index do |simplex, j|
          column = boundary_positions(simplex, position)
          until column.empty?
            killer = low[column.last]
            break unless killer

            column = xor_sorted(column, columns[killer])
          end
          columns[j] = column
          if column.empty?
            creator[j] = true
          else
            low[column.last] = j
            killed[column.last] = true
          end
        end

        collect_intervals(simplices, nodes, low, creator, killed)
      end

      # @return [Array<Integer>] sorted positions of the simplex's facets
      def boundary_positions(simplex, position)
        return [] if simplex.dimension == 0

        simplex.vertices.each_index.map { |d| position[simplex.vertices[0...d] + simplex.vertices[d + 1..-1]] }.sort
      end

      # Symmetric difference of two sorted arrays (addition of F2 chains).
      def xor_sorted(a, b)
        result = []
        i = j = 0
        while i < a.size && j < b.size
          if a[i] < b[j]
            result << a[i]
            i += 1
          elsif a[i] > b[j]
            result << b[j]
            j += 1
          else
            i += 1
            j += 1
          end
        end
        result.concat(a[i..-1]) if i < a.size
        result.concat(b[j..-1]) if j < b.size
        result
      end

      def collect_intervals(simplices, nodes, low, creator, killed)
        intervals = []
        low.each_pair do |birth_pos, death_pos|
          born = simplices[birth_pos]
          dies = simplices[death_pos]
          intervals << [PersistenceInterval.new(dimension: born.dimension, birth: born.value, death: dies.value,
                                                birth_simplex: labels(born, nodes), death_simplex: labels(dies, nodes)),
                        [born.dimension, born.value, dies.value, born.vertices, dies.vertices]]
        end
        simplices.each_with_index do |simplex, pos|
          next unless creator[pos] && !killed[pos]
          # the filtration is truncated at dimension 2, so an unpaired
          # triangle is an artifact of the truncation, not an H0/H1 class
          next if simplex.dimension > 1

          intervals << [PersistenceInterval.new(dimension: simplex.dimension, birth: simplex.value,
                                                death: Float::INFINITY, birth_simplex: labels(simplex, nodes),
                                                death_simplex: nil),
                        [simplex.dimension, simplex.value, Float::INFINITY, simplex.vertices, []]]
        end
        intervals.sort_by { |(_, sort_key)| sort_key }.map(&:first)
      end

      def labels(simplex, nodes)
        simplex.vertices.map { |i| nodes[i] }
      end
    end
  end
end
