//* This file is part of the MOOSE framework
//* https://www.mooseframework.org
//*
//* All rights reserved, see COPYRIGHT for full restrictions
//* https://github.com/idaholab/moose/blob/master/COPYRIGHT
//*
//* Licensed under LGPL 2.1, please see LICENSE for details
//* https://www.gnu.org/licenses/lgpl-2.1.html

#pragma once

// MOOSE includes
#include "PointVariableSamplerBase.h"

class PointValueSamplerCSV : public PointVariableSamplerBase
{
public:
  static InputParameters validParams();

  PointValueSamplerCSV(const InputParameters & parameters);

  virtual void initialize() override;

protected:
  void readCSVFile();   // Added for CSV data points input (Jim March 13, 2025) // Read points from a CSV file

private:
//   std::vector<Point> _points;   // Added for CSV data points input (Jim March 13, 2025)// Vector to store points read from the CSV file
  std::vector<size_t> indices;  // Modified and Removed for CSV data points input (Jim March 17, 2025) // Added for CSV data points input (Jim March 16, 2025)

};