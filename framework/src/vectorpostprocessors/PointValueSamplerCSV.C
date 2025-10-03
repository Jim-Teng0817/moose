//* This file is part of the MOOSE framework
//* https://www.mooseframework.org
//*
//* All rights reserved, see COPYRIGHT for full restrictions
//* https://github.com/idaholab/moose/blob/master/COPYRIGHT
//*
//* Licensed under LGPL 2.1, please see LICENSE for details
//* https://www.gnu.org/licenses/lgpl-2.1.html

#include "PointValueSamplerCSV.h"

#include <numeric>

registerMooseObject("MooseApp", PointValueSamplerCSV);

InputParameters
PointValueSamplerCSV::validParams()
{
  InputParameters params = PointVariableSamplerBase::validParams();     

  // params.addClassDescription("Sample a variable at specific points.");  // Modified and Removed for CSV data points input (Jim March 13, 2025)
  // params.addRequiredParam<std::vector<Point>>(        // Modified and Removed for CSV data points input (Jim March 13, 2025)
  //     "points", "The points where you want to evaluate the variables");

   
  params.addClassDescription("Sample a variable at specific points loaded from a CSV file.");   // Added for CSV data points input (Jim March 13, 2025)
  params.addRequiredParam<FileName>("samples_file", "CSV file containing the sample points (x, y, z).");  // Added for CSV data points input (Jim March 13, 2025)
  params.addParam<std::vector<size_t>>(          // Modified and Removed for CSV data points input (Jim March 17, 2025) // Added for CSV data points input (Jim March 15, 2025)
    "column_indices",
    "Column indices in the CSV file to be sampled from. Number of indices here "
    "will be the same as the number of columns per matrix.");
  
  params.addParam<std::vector<Real>>(    // Added for CSV data points input (Jim Sep 27, 2025)
    "default_values",
    {300.0, 0.0, 0.0},     // This samples: temp, temperature_gradient, and solidification_rate If only sample temp => {300.0},
    "Default values if a sample point is not found. "
    "Order should match the variables being sampled.");

  // params.addParam<std::vector<std::string>>(          // Modified and Removed for CSV data points input (Jim March 17, 2025) // Added for CSV data points input (Jim March 15, 2025)
  //   "column_names",
  //   "Column names in the CSV file to be sampled from. Number of columns names "
  //   "here will be the same as the number of columns per matrix.");
  return params;
}

PointValueSamplerCSV::PointValueSamplerCSV(const InputParameters & parameters)
  : PointVariableSamplerBase(parameters)
{
  // _points = getParam<std::vector<Point>>("points");  // Modified and Removed for CSV data points input (Jim March 13, 2025)


  FileName csv_file = getParam<FileName>("samples_file");   // Added for CSV data points input (Jim March 13, 2025)
  std::vector<size_t> indices = getParam<std::vector<size_t>>("column_indices");      // Added for CSV data points input (Jim March 17, 2025)
  // std::vector<dof_id_type> indices = getParam<std::vector<dof_id_type>>("column_indices");   // Modified and Removed for CSV data points input (Jim March 17, 2025) // Added for CSV data points input (Jim March 13, 2025)

  

  MooseUtils::DelimitedFileReader reader(getParam<FileName>("samples_file"), &_communicator);   // Added for CSV data points input (Jim March 16, 2025)  from CSVSampler.C
  reader.read();    // Added for CSV data points input (Jim March 16, 2025)  from CSVSampler.C

  if (indices.size() != 3)         // Added for CSV data points input (Jim March 16, 2025)
    mooseError("Must provide exactly 3 column indices for x, y, and z coordinates.");

  const std::vector<Real> & x_coords = reader.getData(indices[0]);    // Added for CSV data points input (Jim March 13, 2025)   
  // std::cout << "location@x: ";
  // for (const auto & val : x_coords)
  // {
  //   std::cout << val << " ";
  // }
  // std::cout << std::endl;

  const std::vector<Real> & y_coords = reader.getData(indices[1]);    // Added for CSV data points input (Jim March 13, 2025)
  // std::cout << "location@y: ";
  // for (const auto & val : y_coords)
  // {
  //   std::cout << val << " ";
  // }
  // std::cout << std::endl;

  const std::vector<Real> & z_coords = reader.getData(indices[2]);    // Added for CSV data points input (Jim March 13, 2025)
  // std::cout << "location@z: ";
  // for (const auto & val : z_coords)
  // {
  //   std::cout << val << " ";
  // }
  // std::cout << std::endl;

  if (x_coords.size() != y_coords.size() || x_coords.size() != z_coords.size())     // Added for CSV data points input (Jim March 16, 2025)
    mooseError("CSV file must have the same number of entries for x, y, and z coordinates.");

  _points.clear();    // Added for CSV data points input (Jim March 13, 2025)
  for (size_t i = 0; i < x_coords.size(); i++)   // Added for CSV data points input (Jim March 13, 2025)  use size_t for store large data safely and no signed/unsigned mismatch
  {
    _points.emplace_back(Point(x_coords[i], y_coords[i], z_coords[i]));
  }

  // std::cout << "_points: ";
  // for (const auto & point : _points)
  // {
  //   std::cout << "(" << point(0) << ", " << point(1) << ", " << point(2) << ") ";
  // }
  // std::cout << std::endl;
}



void
PointValueSamplerCSV::initialize()
{
  // std::cout << "_points_before_initialization: ";
  // for (const auto & point : _points)
  // {
  //   std::cout << "(" << point(0) << ", " << point(1) << ", " << point(2) << ") ";
  // }
  // std::cout << std::endl;
  // std::cout << "_points.size_before_initialization" << _points.size() << std::endl;

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

  // std::cout << "_points_after_initialization: ";
  // for (const auto & point : _points)
  // {
  //   std::cout << "(" << point(0) << ", " << point(1) << ", " << point(2) << ") ";
  // }
  // std::cout << std::endl;
  // std::cout << "_points.size_after_initialization" << _points.size() << std::endl;
  PointVariableSamplerBase::initialize();
<<<<<<< HEAD
}


void
PointValueSamplerCSV::finalize()   // Added for CSV data points input (Jim Sep 27, 2025)
{
  // Loop over all points
  for (MooseIndex(_found_points) i = 0; i < _found_points.size(); ++i)
  {
    // If the point was not found, set default values
    if (!_found_points[i])
    {
      // mooseWarning("In ", name(), ", sample point not found: ", _points[i], ". Using default values.");
      _point_values[i] = _default_values; // _default_values is a std::vector<Real> with your defaults
    }

    // Add sample for all points
    SamplerBase::addSample(_points[i], _ids[i], _point_values[i]);
  }
}

