//* This file is part of the MOOSE framework
//* https://mooseframework.inl.gov
//*
//* All rights reserved, see COPYRIGHT for full restrictions
//* https://github.com/idaholab/moose/blob/master/COPYRIGHT
//*
//* Licensed under LGPL 2.1, please see LICENSE for details
//* https://www.gnu.org/licenses/lgpl-2.1.html

#include "PointSamplerBase.h"

// MOOSE includes
#include "MooseMesh.h"
#include "Assembly.h"

#include "libmesh/mesh_tools.h"

InputParameters
PointSamplerBase::validParams()
{
  InputParameters params = GeneralVectorPostprocessor::validParams();

  params += SamplerBase::validParams();

  params.addParam<PostprocessorName>(
      "scaling", 1.0, "The postprocessor that the variables are multiplied with");
  params.addParam<bool>(
      "warn_discontinuous_face_values",
      true,
      "Whether to return a warning if a discontinuous variable is sampled on a face");
  params.addParam<Real>(
    "OB_Temp",
    300.0,
    "The temperature out of the block");          // Added to test effect of Out of Block Temp. (Jim Feb. 13, 2026)

  return params;
}

PointSamplerBase::PointSamplerBase(const InputParameters & parameters)
  : GeneralVectorPostprocessor(parameters),
    SamplerBase(parameters, this, _communicator),
    _mesh(_subproblem.mesh()),
    _pp_value(getPostprocessorValue("scaling")),
    _ob_temp(getParam<Real>("OB_Temp")),          // Added to test effect of Out of Block Temp. (Jim Feb. 13, 2026)
    _warn_discontinuous_face_values(getParam<bool>("warn_discontinuous_face_values")),
    _discontinuous_at_faces(false)
{
}

void
PointSamplerBase::initialize()
{
  // Generate new Ids if the point vector has grown (non-negative counting numbers)
  if (_points.size() > _ids.size())
  {
    auto old_size = _ids.size();
    _ids.resize(_points.size());
    std::iota(_ids.begin() + old_size, _ids.end(), old_size);
  }
  // Otherwise sync the ids array to be smaller if the point vector has been shrunk
  else if (_points.size() < _ids.size())
    _ids.resize(_points.size());

  SamplerBase::initialize();

  // We do this here just in case it's been destroyed and recreated because of mesh adaptivity.
  _pl = _mesh.getPointLocator();

  // We may not find a requested point on a distributed mesh, and
  // that's okay.
  _pl->enable_out_of_mesh_mode();

  // Reset the point arrays
  _found_points.assign(_points.size(), false);

  _point_values.resize(_points.size());
  std::for_each(
      _point_values.begin(), _point_values.end(), [](std::vector<Real> & vec) { vec.clear(); });
}

void
PointSamplerBase::finalize()
{
  // Save off for speed
  const auto pid = processor_id();

  // Consolidate _found_points across processes to know which points were found
  auto _global_found_points = _found_points;
  _comm.sum(_global_found_points);

  // Keep track of maximum process ids for each point to only add it once
  std::vector<unsigned int> max_pid(_found_points.size());
  _comm.maxloc(_found_points, max_pid);

  for (MooseIndex(_found_points) i = 0; i < _found_points.size(); ++i)
  {
    // _global_found_points should contain all 1's at this point (ie every point was found by a
    // proc)
    if (pid == 0 && !_global_found_points[i])
    {
      // mooseError("In ", name(), ", sample point not found: ", _points[i]);     // Modified and Removed for CSV data points input (Jim March 30, 2025)

      // mooseWarning("In ", name(), ", sample point not found: ", _points[i], ". Setting default value.");     // Added for CSV data points input (Jim March 30, 2025)

      // _point_values[i] = std::vector<double>{300.0, 0.0, 0.0};     // Modified for CSV data points input (Jim Sep. 27, 2025) //set default value to be 300 K (Room Temp.), solidification rate, temperature gradient      SamplerBase::addSample(_points[i], _ids[i], _point_values[i]);     // Added for CSV data points input (Jim March 30, 2025)
      // _point_values[i] = std::vector<double>{300.0};   // Modified for CSV data points input (Jim Nov. 04, 2025)
      _point_values[i] = std::vector<double>{_ob_temp};   // Modified for CSV data points input (Jim Feb. 13, 2026)

      SamplerBase::addSample(_points[i], _ids[i], _point_values[i]);   // Added for CSV data points input (Jim Nov. 05, 2025)
      continue; // done for this point   // Added for CSV data points input (Jim Nov. 05, 2025)
    }

    // only process that found the point has the value, and only process with max id should add
    if (pid == max_pid[i] && _found_points[i])
      SamplerBase::addSample(_points[i], _ids[i], _point_values[i]);
  }

  SamplerBase::finalize();
}

const Elem *
PointSamplerBase::getLocalElemContainingPoint(const Point & p)
{
  const Elem * elem = nullptr;
  if (_discontinuous_at_faces)
  {
    libmesh_parallel_only(comm());

    // Get all possible elements the point may be in
    std::set<const Elem *> candidate_elements;
    (*_pl)(p, candidate_elements);

    // Look at all the element IDs
    std::set<dof_id_type> candidate_ids;
    for (auto candidate : candidate_elements)
      candidate_ids.insert(candidate->id());

    comm().set_union(candidate_ids);

    // Domains without candidate elements will not own the lowest ID one
    if (candidate_elements.size())
    {
      // If we know of the minimum, this will be valid. Otherwise, it'll be
      // nullptr which is fine
      elem = _mesh.queryElemPtr(*(candidate_ids.begin()));

      // Print a warning if it's on a face and a variable is discontinuous
      if (_warn_discontinuous_face_values && candidate_ids.size() > 1)
        mooseDoOnce(mooseWarning("A discontinuous variable is sampled on a face, at ", p));
    }
  }
  else // continuous variables
  {
    // Get all possible elements the point may be in
    // We cant just locate in one element because at the edge between two process domains, it could
    // be that both domains find the element that is not within their domain
    std::set<const Elem *> candidate_elements;
    (*_pl)(p, candidate_elements);

    // Only keep the one that may be local
    for (auto candidate : candidate_elements)
      if (candidate->processor_id() == processor_id())
        elem = candidate;
  }

  if (elem && elem->processor_id() == processor_id())
    return elem;

  return nullptr;
}
