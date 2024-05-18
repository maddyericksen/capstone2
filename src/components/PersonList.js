import React from 'react';
import axios from 'axios';

export default class PersonList extends React.Component {
  state = {
    persons: []
  }

  componentDidMount() {
//  Group3 Capstone 2A (UI) created API Gateway endpoint
//    axios.get(`https://kd4yg1xjia.execute-api.us-west-2.amazonaws.com/prod/get-todo`)
//  Group3 Capstone 2B (Terraform) created API Gateway endpoint
    axios.get(`https://w2ry0j0d9l.execute-api.us-west-2.amazonaws.com/prod/get-todo`)
      .then(res => {
        const persons = res.data.body;
        this.setState({ persons });
      })
  }

  render() {
    return (
      <ul>
        {
          this.state.persons
            .map(person =>
              <li key={person.id}>{person.id}{person.name}</li>
            )
        }
      </ul>
    )
  }
}