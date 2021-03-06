/* 
 * Contains unit tests for an implementation of the Graph500 benchmark
 * graph search algorithm.
 *
 *  Created on: 2013-05-31
 *      Author: Abdullah Gharaibeh
 */

// totem includes
#include "totem_common_unittest.h"

#if GTEST_HAS_PARAM_TEST

using ::testing::TestWithParam;
using ::testing::Values;

typedef error_t(*Graph500Function)(graph_t*, vid_t, bfs_tree_t*);

// Allows testing the vanilla graph500 functions and the ones based on Totem
typedef struct graph500_param_s {
  totem_attr_t*    attr;   // Totem attributes for totem-based tests
  Graph500Function func;   // the vanilla Graph500 function if attr is NULL
} graph500_param_t;

class Graph500Test : public TestWithParam<graph500_param_t*> {
 public:
  virtual void SetUp() {
    // Ensure the minimum CUDA architecture is supported
    CUDA_CHECK_VERSION();
    _graph500_param = GetParam();
    _mem_type = TOTEM_MEM_HOST_PINNED;
    _graph = NULL;
    _tree = NULL;
  }
  virtual void TearDown() {
    if (_graph) graph_finalize(_graph);
  }

  void InitTestCase(const char* filename) {
    graph_initialize(filename, false, &_graph);
    CALL_SAFE(totem_malloc(_graph->vertex_count * sizeof(bfs_tree_t), _mem_type,
                           (void**)&_tree));
  }

  void FinalizeTestCase() {
    totem_free(_tree, _mem_type);
  }

  error_t TestGraph(vid_t src) {
    if (_graph500_param->attr) {
      _graph500_param->attr->push_msg_size = 
        (sizeof(vid_t) * BITS_PER_BYTE) + 1;
      _graph500_param->attr->alloc_func = graph500_alloc;
      _graph500_param->attr->free_func = graph500_free;
      if (totem_init(_graph, _graph500_param->attr) == FAILURE) {
        return FAILURE;
      }
      error_t err = graph500_hybrid(src, _tree);
      totem_finalize();
      return err;
    }
    return _graph500_param->func(_graph, src, _tree);
  }
 protected:
  graph500_param_t* _graph500_param;
  totem_mem_t _mem_type;
  graph_t* _graph;
  bfs_tree_t* _tree;
};

TEST_P(Graph500Test, Empty) {
  _graph = (graph_t*)calloc(1, sizeof(graph_t));
  EXPECT_EQ(FAILURE, TestGraph(0));
  EXPECT_EQ(FAILURE, TestGraph(99));
  free(_graph);
  _graph = NULL;
}

TEST_P(Graph500Test, SingleNode) {
  InitTestCase(DATA_FOLDER("single_node.totem"));
  EXPECT_EQ(SUCCESS, TestGraph(0));
  EXPECT_EQ((vid_t)0, (vid_t)_tree[0]);
  EXPECT_EQ(FAILURE, TestGraph(1));
  FinalizeTestCase();
}

TEST_P(Graph500Test, SingleNodeLoop) {
  InitTestCase(DATA_FOLDER("single_node_loop.totem"));
  EXPECT_EQ(SUCCESS, TestGraph(0));
  EXPECT_EQ((vid_t)0, (vid_t)_tree[0]);
  EXPECT_EQ(FAILURE, TestGraph(1));
  FinalizeTestCase();
}

// Completely disconnected graph
TEST_P(Graph500Test, Disconnected) {
  InitTestCase(DATA_FOLDER("disconnected_1000_nodes.totem"));

  // First vertex as source
  vid_t source = 0;
  EXPECT_EQ(SUCCESS, TestGraph(source));
  EXPECT_EQ(source, (vid_t)_tree[source]);
  for(vid_t vertex = source + 1; vertex < _graph->vertex_count; vertex++) {
    EXPECT_EQ(VERTEX_ID_MAX, (vid_t)_tree[vertex]);
  }

  // Last vertex as source
  source = _graph->vertex_count - 1;
  EXPECT_EQ(SUCCESS, TestGraph(source));
  EXPECT_EQ(source, (vid_t)_tree[source]);
  for(vid_t vertex = source; vertex < _graph->vertex_count - 1; vertex++){
    EXPECT_EQ(VERTEX_ID_MAX, (vid_t)_tree[vertex]);
  }

  // A vertex in the middle as source
  source = 199;
  EXPECT_EQ(SUCCESS, TestGraph(source));
  for(vid_t vertex = 0; vertex < _graph->vertex_count; vertex++) {
    EXPECT_EQ((vertex == source) ? source : 
              VERTEX_ID_MAX, (vid_t)_tree[vertex]);
  }

  // Non existent vertex source
  EXPECT_EQ(FAILURE, TestGraph(_graph->vertex_count));

  FinalizeTestCase();
}

// Chain of 1000 nodes.
TEST_P(Graph500Test, Chain) {
  InitTestCase(DATA_FOLDER("chain_1000_nodes.totem"));

  // First vertex as source
  vid_t source = 0;
  EXPECT_EQ(SUCCESS, TestGraph(source));
  EXPECT_EQ(source, (vid_t)_tree[source]);
  for(vid_t vertex = source + 1; vertex < _graph->vertex_count; vertex++){
    EXPECT_EQ((vertex - 1), (vid_t)_tree[vertex]);
  }

  // Last vertex as source
  source = _graph->vertex_count - 1;
  EXPECT_EQ(SUCCESS, TestGraph(source));
  EXPECT_EQ(source, (vid_t)_tree[source]);
  for(vid_t vertex = source; vertex < _graph->vertex_count - 1; vertex++){
    EXPECT_EQ((vertex + 1), (vid_t)_tree[vertex]);
  }

  // A vertex in the middle as source
  source = 199;
  EXPECT_EQ(SUCCESS, TestGraph(source));
  for(vid_t vertex = 0; vertex < _graph->vertex_count; vertex++) {
    if (vertex > source) {
      EXPECT_EQ((vertex - 1), (vid_t)_tree[vertex]);
    } else if (vertex < source) {
      EXPECT_EQ((vertex + 1), (vid_t)_tree[vertex]);
    } else {
      EXPECT_EQ(source, (vid_t)_tree[vertex]);
    }
  }

  // Non existent vertex source
  EXPECT_EQ(FAILURE, TestGraph(_graph->vertex_count));

  FinalizeTestCase();
}

// Complete graph of 300 nodes.
TEST_P(Graph500Test, CompleteGraph) {
  InitTestCase(DATA_FOLDER("complete_graph_300_nodes.totem"));

  // First vertex as source
  vid_t source = 0;
  EXPECT_EQ(SUCCESS, TestGraph(source));
  for(vid_t vertex = 0; vertex < _graph->vertex_count; vertex++){
    EXPECT_EQ(source, (vid_t)_tree[vertex]);
  }

  // Last vertex as source
  source = _graph->vertex_count - 1;
  EXPECT_EQ(SUCCESS, TestGraph(source));
  for(vid_t vertex = 0; vertex < _graph->vertex_count; vertex++) {
    EXPECT_EQ(source, (vid_t)_tree[vertex]);
  }

  // A vertex source in the middle
  source = 199;
  EXPECT_EQ(SUCCESS, TestGraph(source));
  for(vid_t vertex = 0; vertex < _graph->vertex_count; vertex++) {
    EXPECT_EQ(source, (vid_t)_tree[vertex]);
  }

  // Non existent vertex source
  EXPECT_EQ(FAILURE, TestGraph(_graph->vertex_count));

  FinalizeTestCase();
}

// Star graph of 1000 nodes.
TEST_P(Graph500Test, Star) {
  InitTestCase(DATA_FOLDER("star_1000_nodes.totem"));

  // First vertex as source
  vid_t source = 0;
  EXPECT_EQ(SUCCESS, TestGraph(source));
  for(vid_t vertex = 0; vertex < _graph->vertex_count; vertex++){
    EXPECT_EQ(source, (vid_t)_tree[vertex]);
  }

  // Last vertex as source
  source = _graph->vertex_count - 1;
  EXPECT_EQ(SUCCESS, TestGraph(source));
  EXPECT_EQ(source, (vid_t)_tree[source]);
  EXPECT_EQ(source, (vid_t)_tree[0]);
  for(vid_t vertex = 1; vertex < _graph->vertex_count; vertex++) {
    if (vertex == source) continue;
    EXPECT_EQ((vid_t)0, (vid_t)_tree[vertex]);
  }

  // A vertex source in the middle
  source = 199;
  EXPECT_EQ(SUCCESS, TestGraph(source));
  EXPECT_EQ(source, (vid_t)_tree[source]);
  EXPECT_EQ(source, (vid_t)_tree[0]);
  for(vid_t vertex = 1; vertex < _graph->vertex_count; vertex++) {
    if (vertex == source) continue;
    EXPECT_EQ((vid_t)0, (vid_t)_tree[vertex]);
  }

  // Non existent vertex source
  EXPECT_EQ(FAILURE, TestGraph(_graph->vertex_count));

  FinalizeTestCase();
}

// Values() seems to accept only pointers, hence the possible parameters
// are defined here, and a pointer to each of them is used.
graph500_param_t graph500_params[] = {
  {NULL, &graph500_cpu},
  {&totem_attrs[0], NULL},
  {&totem_attrs[1], NULL},
  {&totem_attrs[2], NULL},
  {&totem_attrs[3], NULL},
  {&totem_attrs[4], NULL},
  {&totem_attrs[5], NULL},
  {&totem_attrs[6], NULL},
  {&totem_attrs[7], NULL},
  {&totem_attrs[8], NULL},
  {&totem_attrs[9], NULL},
  {&totem_attrs[10], NULL},
  {&totem_attrs[11], NULL},
  {&totem_attrs[12], NULL},
  {&totem_attrs[13], NULL},
  {&totem_attrs[14], NULL},
  {&totem_attrs[15], NULL},
  {&totem_attrs[16], NULL},
  {&totem_attrs[17], NULL},
  {&totem_attrs[18], NULL},
  {&totem_attrs[19], NULL},
  {&totem_attrs[20], NULL},
  {&totem_attrs[21], NULL},
  {&totem_attrs[22], NULL},
  {&totem_attrs[23], NULL}
};

// From Google documentation:
// In order to run value-parameterized tests, we need to instantiate them,
// or bind them to a list of values which will be used as test parameters.
//
// Values() receives a list of parameters and the framework will execute the
// whole set of tests Graph500Test for each element of Values()
INSTANTIATE_TEST_CASE_P(Graph500GPUAndCPUTest, Graph500Test, 
                        Values(&graph500_params[0],
                               &graph500_params[1],
                               &graph500_params[2],
                               &graph500_params[3],
                               &graph500_params[4],
                               &graph500_params[5],
                               &graph500_params[6],
                               &graph500_params[7],
                               &graph500_params[8],
                               &graph500_params[9],
                               &graph500_params[10],
                               &graph500_params[11],
                               &graph500_params[12],
                               &graph500_params[13],
                               &graph500_params[14],
                               &graph500_params[15],
                               &graph500_params[16],
                               &graph500_params[17],
                               &graph500_params[18],
                               &graph500_params[19],
                               &graph500_params[20],
                               &graph500_params[21],
                               &graph500_params[22],
                               &graph500_params[23],
                               &graph500_params[24]));

#else

// From Google documentation:
// Google Test may not support value-parameterized tests with some
// compilers. This dummy test keeps gtest_main linked in.
TEST_P(DummyTest, ValueParameterizedTestsAreNotSupportedOnThisPlatform) {}

#endif  // GTEST_HAS_PARAM_TEST
