import React from 'react';
import _ from 'lodash';

const group2OrGroup1CsdWorkshops = {
  'June 18 - 23, 2017: Houston': ['AL', 'FL', 'GA', 'IN', 'IA', 'KY', 'OH', 'OK', 'SC', 'TN', 'TX'],
  'July 16 - 21, 2017: Phoenix': ['AR', 'AZ', 'CA', 'CO', 'ID', 'MT', 'NV', 'UT', 'WA'],
  'July 30 - August 4, 2017: Philadelphia': ['IL', 'ME', 'MD', 'MI', 'NJ', 'NY', 'NC', 'PA', 'WI', 'VA']
};

const group1CspWorkshops = {
  'A+ College Ready': {region: 'Alabama', workshopDates: ''},
  'Grand Canyon University & Science Foundation Arizona': {region: 'Arizona (Phoenix)', workshopDates: ''},
  'Riverside County Office of Education': {region: 'California (Inland Empire)', workshopDates: 'June 19 - 23, 2017'},
  '9 Dots Community Learning Center': {region: 'California (Los Angeles/Orange County)', workshopDates: ''},
  'Alameda County Office of Education': {region: 'California (Oakland)', workshopDates: ''},
  'Broward County Public Schools': {region: 'Florida (Miami / Broward)', workshopDates: ''},
  'Florida State College Jacksonville': {region: 'Florida (Northeast)', workshopDates: ''},
  'Orlando Science Center': {region: 'Florida (Orlando)', workshopDates: ''},
  'Georgia Tech Center for Education Integrating Science, Mathematics, and Computing': {region: 'Georgia', workshopDates: ''},
  'Idaho Digital Learning Academy': {region: 'Idaho', workshopDates: 'June 19 - 23, 2017'},
  'Lumity': {region: 'Illinois (Chicago)', workshopDates: ''},
  'Nextech': {region: 'Indiana', workshopDates: ''},
  'The Council of Educational Administrative and Supervisory Organizations of Maryland (CEASOM)': {region: 'Maryland', workshopDates: 'August 7 - 11, 2017'},
  'Southern Nevada Regional Professional Development Program': {region: 'Nevada', workshopDates: ''},
  'Code/Interactive': {region: 'New York', workshopDates: 'July 10 - 14, 2017'},
  'The Friday Institute': {region: 'North Carolina (Durham)', workshopDates: 'July 10 - 14, 2017'},
  'Battelle Education': {region: 'Ohio', workshopDates: ''},
  'Rice University': {region: 'Texas (Houston)', workshopDates: 'June 26 - 30, 2017'},
  'Utah STEM Action Center and Utah Board of Education': {region: 'Utah', workshopDates: ''},
  'CodeVA': {region: 'Virginia (Richmond)', workshopDates: 'July 17 - 21, 2017'},
  'Puget Sound Educational Service District': {region: 'Washington (Puget Sound)', workshopDates: 'July 10 - 14, 2017'},
  'NorthEast Washington Educational Service District 101': {region: 'Washington (Spokane)', workshopDates: 'July 10 - 14, 2017'}
};

const SummerWorkshopSchedule = React.createClass({
  propTypes: {
    regionalPartnerGroup: React.PropTypes.number,
    regionalPartnerName: React.PropTypes.string,
    selectedCourse: React.PropTypes.string,
    selectedState: React.PropTypes.string,
    onAssignedWorkshopFound: React.PropTypes.func
  },

  getInitialState() {
    return {
      assignedSummerWorkshop: this.getAssignedWorkshop()
    }
  },

  componentDidUpdate() {
    this.props.onAssignedWorkshopFound({assignedSummerWorkshop: this.getAssignedWorkshop()});
  },

  getAssignedWorkshop() {
    let assignedSummerWorkshop;

    if (this.props.regionalPartnerGroup === 2 || (this.props.regionalPartnerGroup === 1 && this.props.selectedCourse === 'csd')) {
      assignedSummerWorkshop = `Summer 2017 (exact date to be determined) in ${this.props.selectedState}`;

      _.forEach(group2OrGroup1CsdWorkshops, (value, key) => {
        if (value.includes(this.props.selectedState)) {
          assignedSummerWorkshop = key;
        }
      });
    } else if (this.props.regionalPartnerGroup === 1 && this.props.selectedCourse === 'csp') {
      assignedSummerWorkshop = group1CspWorkshops[this.props.regionalPartnerName] || {region: this.props.selectedState, workshopDates: 'Summer 2017 (exact date to be determined)'};
    }

    return assignedSummerWorkshop;
  },

  renderGroup1CsdOrGroup2AssignedWorkshop() {
    if (this.props.regionalPartnerGroup === 2 ||
      (this.props.regionalPartnerGroup === 1 && this.props.selectedCourse === 'csd')) {
      return (
        <div>
          We strongly encourage participants to attend their assigned summer workshop (based on the region in which
          you teach), so that you can meet the other teachers, facilitators, and Regional Partners with whom you will
          work in 2017-18. Your region's assigned summer workshop is:
          <p style={{fontSize: '18px', fontWeight: 'bold'}}>
            {this.getAssignedWorkshop()}
          </p>
        </div>
      );
    }
  },

  renderAssignedWorkshopGroup1Csp() {
    if (this.props.regionalPartnerGroup === 1 && this.props.selectedCourse === 'csp') {
      return (
        <div>
          <label>
            We strongly encourage participants to attend their assigned summer workshop (based on the district in which
            you currently teach), so that you can meet the other teachers, facilitators and Regional Partners with whom
            you will work in 2017 - 18. Your region and summer workshop dates is below.
          </label>
          <label>
            {this.getAssignedWorkshop()}
          </label>
        </div>
      );
    }
  },

  render() {
    return (
      <div>
        {this.renderGroup1CsdOrGroup2AssignedWorkshop()}
        {this.renderAssignedWorkshopGroup1Csp()}
      </div>
    );
  }
});

export {SummerWorkshopSchedule, group2OrGroup1CsdWorkshops};
