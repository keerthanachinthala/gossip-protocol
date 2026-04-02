@external(erlang, "unicode", "characters_to_list")
fn string_to_charlist(s: String) -> List(Int)

@external(erlang, "rand", "uniform")
fn rand_uniform(n: Int) -> Int

pub fn build_topology(num_nodes: Int, topology_type: String) -> List(List(Int)) {
  let chars = string_to_charlist(topology_type)
  let full_chars = [102, 117, 108, 108] // "full"
  let line_chars = [108, 105, 110, 101] // "line"
  let chars_3d = [51, 68] // "3D"
  let chars_imp3d = [105, 109, 112, 51, 68] // "imp3D"
  
  case chars_equal(chars, full_chars) {
    True -> build_full_topology_correct(num_nodes)
    False -> case chars_equal(chars, line_chars) {
      True -> build_line_topology_correct(num_nodes)
      False -> case chars_equal(chars, chars_3d) {
        True -> build_3d_topology(num_nodes)
        False -> case chars_equal(chars, chars_imp3d) {
          True -> build_imperfect_3d_topology(num_nodes)
          False -> build_full_topology_correct(num_nodes)
        }
      }
    }
  }
}

fn chars_equal(chars1: List(Int), chars2: List(Int)) -> Bool {
  case chars1, chars2 {
    [], [] -> True
    [c1, ..rest1], [c2, ..rest2] -> case c1 == c2 {
      True -> chars_equal(rest1, rest2)
      False -> False
    }
    _,_ -> False
  }
}

// KEEPING YOUR WORKING FULL TOPOLOGY
fn build_full_topology_correct(num_nodes: Int) -> List(List(Int)) {
  build_full_correct_helper(0, num_nodes, [])
}

fn build_full_correct_helper(current: Int, max: Int, acc: List(List(Int))) -> List(List(Int)) {
  case current >= max {
    True -> reverse_list(acc)
    False -> {
      let neighbors = get_all_others(current, max)
      build_full_correct_helper(current + 1, max, [neighbors, ..acc])
    }
  }
}

fn get_all_others(current: Int, max: Int) -> List(Int) {
  get_all_others_helper(0, current, max, [])
}

fn get_all_others_helper(i: Int, current: Int, max: Int, acc: List(Int)) -> List(Int) {
  case i >= max {
    True -> reverse_list(acc)
    False -> case i == current {
      True -> get_all_others_helper(i + 1, current, max, acc)  // Skip self
      False -> get_all_others_helper(i + 1, current, max, [i, ..acc])  // Add neighbor
    }
  }
}

// KEEPING YOUR WORKING LINE TOPOLOGY
fn build_line_topology_correct(num_nodes: Int) -> List(List(Int)) {
  build_line_correct_helper(0, num_nodes, [])
}

fn build_line_correct_helper(current: Int, max: Int, acc: List(List(Int))) -> List(List(Int)) {
  case current >= max {
    True -> reverse_list(acc)
    False -> {
      let neighbors = get_line_neighbors_simple(current, max)
      build_line_correct_helper(current + 1, max, [neighbors, ..acc])
    }
  }
}

fn get_line_neighbors_simple(i: Int, num_nodes: Int) -> List(Int) {
  case i {
    0 -> case num_nodes > 1 {
      True -> [1]  // First: only right
      False -> []
    }
    n -> case n == num_nodes - 1 {
      True -> [n - 1]  // Last: only left  
      False -> [n - 1, n + 1]  // Middle: left and right
    }
  }
}

// FIXED: PROPER 3D TOPOLOGY IMPLEMENTATION
fn build_3d_topology(num_nodes: Int) -> List(List(Int)) {
  let side = calculate_cube_side(num_nodes)
  build_3d_grid_helper(0, num_nodes, side, [])
}

// FIXED: PROPER IMPERFECT 3D TOPOLOGY IMPLEMENTATION  
fn build_imperfect_3d_topology(num_nodes: Int) -> List(List(Int)) {
  let side = calculate_cube_side(num_nodes)
  build_imp_3d_helper(0, num_nodes, side, [])
}

// HELPER FUNCTIONS FOR 3D TOPOLOGIES
fn calculate_cube_side(num_nodes: Int) -> Int {
  cube_root_approx(num_nodes, 1)
}

fn cube_root_approx(n: Int, guess: Int) -> Int {
  case guess * guess * guess >= n {
    True -> guess
    False -> cube_root_approx(n, guess + 1)
  }
}

fn build_3d_grid_helper(current: Int, max: Int, side: Int, acc: List(List(Int))) -> List(List(Int)) {
  case current >= max {
    True -> reverse_list(acc)
    False -> {
      let neighbors = get_3d_grid_neighbors(current, side, max)
      build_3d_grid_helper(current + 1, max, side, [neighbors, ..acc])
    }
  }
}

fn build_imp_3d_helper(current: Int, max: Int, side: Int, acc: List(List(Int))) -> List(List(Int)) {
  case current >= max {
    True -> reverse_list(acc)
    False -> {
      let grid_neighbors = get_3d_grid_neighbors(current, side, max)
      let random_neighbor = get_valid_random_neighbor(current, max)
      let all_neighbors = case random_neighbor {
        Ok(rn) -> [rn, ..grid_neighbors]
        Error(_) -> grid_neighbors
      }
      build_imp_3d_helper(current + 1, max, side, [all_neighbors, ..acc])
    }
  }
}

// FIXED: Corrected syntax with curly braces instead of parentheses
fn get_3d_grid_neighbors(index: Int, side: Int, max: Int) -> List(Int) {
  let x = index % side
  let y = {index / side} % side  // FIXED: {} instead of ()
  let z = index / {side * side}  // FIXED: {} instead of ()
  
  let candidates = []
  // X neighbors
  let candidates = case x > 0 {
    True -> [index - 1, ..candidates]
    False -> candidates
  }
  let candidates = case x < side - 1 && index + 1 < max {
    True -> [index + 1, ..candidates]
    False -> candidates
  }
  // Y neighbors  
  let candidates = case y > 0 {
    True -> [index - side, ..candidates]
    False -> candidates
  }
  let candidates = case y < side - 1 && index + side < max {
    True -> [index + side, ..candidates]
    False -> candidates
  }
  // Z neighbors
  let candidates = case z > 0 {
    True -> [index - {side * side}, ..candidates]  // FIXED: {} instead of ()
    False -> candidates
  }
  let candidates = case z < side - 1 && index + {side * side} < max {  // FIXED: {} instead of ()
    True -> [index + {side * side}, ..candidates]  // FIXED: {} instead of ()
    False -> candidates
  }
  
  candidates
}

fn get_valid_random_neighbor(current: Int, max: Int) -> Result(Int, Nil) {
  try_random_neighbor(current, max, 10)
}

fn try_random_neighbor(current: Int, max: Int, attempts: Int) -> Result(Int, Nil) {
  case attempts <= 0 {
    True -> Error(Nil)
    False -> {
      let candidate = rand_uniform(max) - 1
      case candidate == current {
        True -> try_random_neighbor(current, max, attempts - 1)
        False -> Ok(candidate)
      }
    }
  }
}

// KEEPING YOUR EXISTING HELPER FUNCTIONS
fn reverse_list(list: List(a)) -> List(a) {
  reverse_helper(list, [])
}

fn reverse_helper(list: List(a), acc: List(a)) -> List(a) {
  case list {
    [] -> acc
    [first, ..rest] -> reverse_helper(rest, [first, ..acc])
  }
}